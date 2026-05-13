<#
.SYNOPSIS
    Gap-analysis check functions, one per row in best-practices.json.

.DESCRIPTION
    Each function takes a single $Inventory parameter — the in-memory object built by
    Get-SentinelGap from the _raw/ JSON files — and returns either:

      $null                   : no gap detected (rule passes)
      [pscustomobject]@{...}  : a finding with Evidence + Detail fields

    Adding a new rule is a two-step process: drop a Test-* function in this file, add a
    row to best-practices.json that references it by name. The engine wires the rest.

.NOTES
    Author:         noodlemctwoodle
    Component:      Sentinel Documenter — Gap Engine
#>

Set-StrictMode -Version Latest

# Helper — produces a Finding object with consistent shape.
function New-Finding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Evidence,
        [Parameter(Mandatory = $false)]
        [object]$Detail = $null
    )
    [pscustomobject]@{
        Evidence = $Evidence
        Detail   = $Detail
    }
}

# Helper — returns a property if it exists, else default. Sentinel/LA REST occasionally
# returns objects with subtly different property shapes between API versions; this lets
# checks stay tolerant.
function Get-PropOrDefault {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [object]$Object,
        [Parameter(Mandatory = $true)] [string]$Path,
        [Parameter(Mandatory = $false)] $Default = $null
    )
    if ($null -eq $Object) { return $Default }
    $current = $Object
    foreach ($segment in $Path -split '\.') {
        if ($null -eq $current) { return $Default }
        if ($current -is [hashtable] -and $current.ContainsKey($segment)) {
            $current = $current[$segment]
        } elseif ($current.PSObject.Properties.Name -contains $segment) {
            $current = $current.$segment
        } else {
            return $Default
        }
    }
    if ($null -eq $current) { return $Default }
    return $current
}

# ------------------------------------------------------------
# SENT-001 — Daily cap not configured
# ------------------------------------------------------------
function Test-DailyCapConfigured {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    $cap = Get-PropOrDefault $Inventory.Workspace 'properties.workspaceCapping.dailyQuotaGb' -1
    if ($null -eq $cap -or $cap -eq -1) {
        return New-Finding -Evidence 'workspaceCapping.dailyQuotaGb is unset (-1 = unlimited).' -Detail @{ DailyQuotaGb = $cap }
    }
    return $null
}

# ------------------------------------------------------------
# SENT-002 — Workspace default retention < 90d
# ------------------------------------------------------------
function Test-WorkspaceRetentionMeetsSentinelBenefit {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    $retention = Get-PropOrDefault $Inventory.Workspace 'properties.retentionInDays' 0
    if ([int]$retention -lt 90) {
        return New-Finding -Evidence "Workspace default retention is $retention days; Sentinel includes the 30->90d upgrade at no extra cost on eligible tables." -Detail @{ RetentionInDays = [int]$retention }
    }
    return $null
}

# ------------------------------------------------------------
# SENT-003 — High-volume table on Analytics with no transform
# ------------------------------------------------------------
function Test-NoisyTableHasTransform {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    if (-not $Inventory.TablesWithData) { return $null }
    $threshold = 50.0
    $candidates = @($Inventory.TablesWithData | Where-Object {
        ([double](Get-PropOrDefault $_ 'BillableLast30d' 0)) -ge $threshold
    })
    if (-not $candidates) { return $null }

    $tablesWithTransform = @{}
    foreach ($dcr in @($Inventory.Dcrs)) {
        $flows = Get-PropOrDefault $dcr 'properties.dataFlows' @()
        foreach ($flow in @($flows)) {
            $transform = Get-PropOrDefault $flow 'transformKql' ''
            $output    = Get-PropOrDefault $flow 'outputStream' ''
            if ($transform -and $output) {
                $tablesWithTransform[$output] = $true
            }
        }
    }

    $missing = @($candidates | Where-Object {
        -not $tablesWithTransform.ContainsKey("Microsoft-Table-$($_.DataType)") -and
        -not $tablesWithTransform.ContainsKey("Custom-$($_.DataType)")
    })
    if ($missing.Count -gt 0) {
        $names = ($missing | Select-Object -ExpandProperty DataType) -join ', '
        return New-Finding -Evidence "High-volume Analytics-plan tables with no DCR transform: $names." -Detail @{ Tables = $names }
    }
    return $null
}

# ------------------------------------------------------------
# SENT-004 — Recommended connectors not deployed
# ------------------------------------------------------------
function Test-RecommendedConnectorsDeployed {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    # $Inventory.DataConnectors can be $null when the workspace has no classic
    # connectors at all (some tenants run pure CCF). Coerce to an empty array
    # so Get-PropOrDefault doesn't see a $null Object.
    $connectors = @()
    if ($Inventory.DataConnectors) { $connectors = @($Inventory.DataConnectors) }
    $deployedKinds = @($connectors | ForEach-Object { Get-PropOrDefault $_ 'kind' '' }) | Sort-Object -Unique
    $recommended = @('AzureActiveDirectory','MicrosoftThreatProtection','AzureSecurityCenter','Office365','MicrosoftDefenderAdvancedThreatProtection','ThreatIntelligence')
    $missing = @($recommended | Where-Object { $deployedKinds -notcontains $_ })
    if ($missing.Count -gt 0) {
        return New-Finding -Evidence "Recommended connector kinds not deployed: $($missing -join ', ')." -Detail @{ Missing = $missing }
    }
    return $null
}

# ------------------------------------------------------------
# SENT-005 — UEBA disabled
# ------------------------------------------------------------
function Test-UebaEnabled {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    $ueba = Get-PropOrDefault $Inventory.Settings 'Ueba'

    # Data-presence inference: when UEBA is producing rows in any of its
    # tables, treat the workspace as "effectively on" regardless of whether
    # the settings resource was written. The portal toggle leaves the
    # configuration resource absent, so a settings-only check produces a
    # false positive on the common case. The producing-data signal is
    # captured separately by the exporter as ueba-data-presence.json.
    $presence = @()
    if ($Inventory.PSObject.Properties.Name -contains 'UebaDataPresence') {
        $presence = @($Inventory.UebaDataPresence)
    }
    $producingCount = 0
    foreach ($row in $presence) {
        if (-not $row) { continue }
        $c = Get-PropOrDefault $row 'Count'
        if ($null -ne $c) {
            $n = 0
            if ([int]::TryParse([string]$c, [ref]$n)) { $producingCount += $n }
        }
    }
    if ($producingCount -gt 0) { return $null }

    if ($null -eq $ueba) {
        return New-Finding -Evidence 'No Ueba setting resource found on the workspace and no rows observed in BehaviorAnalytics / IdentityInfo / UserPeerAnalytics in the last 12 days.'
    }
    $enabled = Get-PropOrDefault $ueba 'properties.dataSources'
    if (-not $enabled -or $enabled.Count -eq 0) {
        return New-Finding -Evidence 'UEBA is configured but no data sources are enabled, and no rows observed in BehaviorAnalytics / IdentityInfo / UserPeerAnalytics in the last 12 days.' -Detail $ueba
    }
    return $null
}

# ------------------------------------------------------------
# SENT-006 — MITRE tactic with zero enabled rules
# ------------------------------------------------------------
function Test-MitreTacticCoverage {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    if (-not $Inventory.MitreTactics) { return $null }
    $coveredTactics = @{}
    foreach ($rule in @($Inventory.AlertRules)) {
        $enabled = Get-PropOrDefault $rule 'properties.enabled' $false
        if (-not $enabled) { continue }
        $tactics = Get-PropOrDefault $rule 'properties.tactics' @()
        foreach ($t in @($tactics)) { $coveredTactics[$t] = $true }
    }
    $uncovered = @($Inventory.MitreTactics | Where-Object { -not $coveredTactics.ContainsKey($_.sentinelShortName) })
    if ($uncovered.Count -gt 0) {
        $names = ($uncovered | Select-Object -ExpandProperty name) -join ', '
        return New-Finding -Evidence "MITRE tactics with zero enabled rules: $names." -Detail @{ UncoveredTactics = $uncovered }
    }
    return $null
}

# ------------------------------------------------------------
# SENT-007 — Rules disabled or in error
# ------------------------------------------------------------
function Test-RulesDisabledOrFailing {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    $bad = @($Inventory.AlertRules | Where-Object {
        $enabled = Get-PropOrDefault $_ 'properties.enabled' $true
        $kind = Get-PropOrDefault $_ 'kind' ''
        # Built-in / Microsoft-managed kinds whose enable-state we don't author.
        $managed = @('Fusion','MicrosoftSecurityIncidentCreation','MLBehaviorAnalytics','ThreatIntelligence')
        ($managed -notcontains $kind) -and (-not $enabled)
    })
    if ($bad.Count -gt 0) {
        $names = ($bad | ForEach-Object { Get-PropOrDefault $_ 'properties.displayName' (Get-PropOrDefault $_ 'name' '?') }) -join '; '
        return New-Finding -Evidence "$($bad.Count) rule(s) disabled: $names." -Detail @{ Count = $bad.Count }
    }
    return $null
}

# ------------------------------------------------------------
# SENT-008 — High-severity templates not deployed
# ------------------------------------------------------------
function Test-HighSeverityTemplatesDeployed {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    $deployedTemplateNames = @{}
    foreach ($r in @($Inventory.AlertRules)) {
        $tn = Get-PropOrDefault $r 'properties.alertRuleTemplateName' ''
        if ($tn) { $deployedTemplateNames[$tn] = $true }
    }
    $missing = @($Inventory.AlertRuleTemplates | Where-Object {
        $sev = Get-PropOrDefault $_ 'properties.severity' 'Low'
        $name = Get-PropOrDefault $_ 'name' ''
        ($sev -eq 'High') -and ($name) -and (-not $deployedTemplateNames.ContainsKey($name))
    })
    if ($missing.Count -gt 0) {
        return New-Finding -Evidence "$($missing.Count) High-severity template(s) not deployed." -Detail @{ Count = $missing.Count }
    }
    return $null
}

# ------------------------------------------------------------
# SENT-009 — Owner/Contributor at workspace scope
# ------------------------------------------------------------
function Test-RbacOverPrivileged {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    $bad = @($Inventory.RbacWorkspace | Where-Object {
        $role = Get-PropOrDefault $_ 'RoleDefinitionName' ''
        $role -in @('Owner','Contributor')
    })
    if ($bad.Count -gt 0) {
        return New-Finding -Evidence "$($bad.Count) Owner/Contributor role assignment(s) at workspace scope." -Detail @{ Count = $bad.Count }
    }
    return $null
}

# ------------------------------------------------------------
# SENT-010 — Diagnostic settings not configured
# ------------------------------------------------------------
function Test-DiagnosticSettingsConfigured {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    if (-not $Inventory.DiagnosticSettings -or @($Inventory.DiagnosticSettings).Count -eq 0) {
        return New-Finding -Evidence 'No diagnostic settings configured on the Log Analytics workspace.'
    }
    return $null
}

# ------------------------------------------------------------
# SENT-011 — Playbook MI lacks Sentinel Responder role
# ------------------------------------------------------------
function Test-PlaybookMiHasResponder {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    if (-not $Inventory.PlaybookMiAssignments -or @($Inventory.PlaybookMiAssignments).Count -eq 0) {
        return $null
    }
    $bad = @($Inventory.PlaybookMiAssignments | Where-Object {
        $roles = Get-PropOrDefault $_ 'WorkspaceRoles' @()
        -not ($roles -contains 'Microsoft Sentinel Responder')
    })
    if ($bad.Count -gt 0) {
        return New-Finding -Evidence "$($bad.Count) playbook managed identity(ies) missing Microsoft Sentinel Responder." -Detail @{ Count = $bad.Count }
    }
    return $null
}

# ------------------------------------------------------------
# SENT-012 — DCR transform missing on noisy custom table
# ------------------------------------------------------------
function Test-DcrTransformMissing {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    $missing = @($Inventory.Dcrs | Where-Object {
        $flows = @(Get-PropOrDefault $_ 'properties.dataFlows' @())
        $hasCustom = $flows | Where-Object { (Get-PropOrDefault $_ 'outputStream' '') -match 'Custom-' }
        $hasTransform = $flows | Where-Object { (Get-PropOrDefault $_ 'transformKql' '') }
        ($hasCustom) -and (-not $hasTransform)
    })
    if ($missing.Count -gt 0) {
        return New-Finding -Evidence "$($missing.Count) DCR(s) target a custom table without transformKql." -Detail @{ Count = $missing.Count }
    }
    return $null
}

# ------------------------------------------------------------
# SENT-013 — Content Hub solution updates available
# ------------------------------------------------------------
function Test-ContentHubUpdatesAvailable {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    if (-not $Inventory.ContentPackages -or -not $Inventory.ContentProductPackages) { return $null }
    $latest = @{}
    foreach ($p in $Inventory.ContentProductPackages) {
        $id = Get-PropOrDefault $p 'properties.contentId' ''
        $v = Get-PropOrDefault $p 'properties.version' ''
        if ($id -and $v) { $latest[$id] = $v }
    }
    $stale = @($Inventory.ContentPackages | Where-Object {
        $id = Get-PropOrDefault $_ 'properties.contentId' ''
        $installed = Get-PropOrDefault $_ 'properties.version' ''
        $id -and $installed -and $latest.ContainsKey($id) -and ($latest[$id] -ne $installed)
    })
    if ($stale.Count -gt 0) {
        return New-Finding -Evidence "$($stale.Count) installed Content Hub solution(s) have a newer version available." -Detail @{ Count = $stale.Count }
    }
    return $null
}

# ------------------------------------------------------------
# SENT-014 — Sentinel still on Azure portal (info-only)
# ------------------------------------------------------------
function Test-OnboardedToDefender {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    # The defender-onboarding state is workspace-specific and exposed via a separate REST
    # surface that may not be in scope. Until we wire that detection, surface the deadline
    # universally as an Info finding so it appears in every report.
    return New-Finding -Evidence 'Sentinel in the Azure portal retires 2027-03-31. Plan the migration to the unified Defender XDR experience.' -Detail @{ Deadline = '2027-03-31' }
}

# ------------------------------------------------------------
# SENT-015 — Commitment-tier opportunity
# ------------------------------------------------------------
function Test-CommitmentTierOpportunity {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    $sku = Get-PropOrDefault $Inventory.Workspace 'properties.sku.name' ''
    if ($sku -ne 'PerGB2018') { return $null }

    $totalGb30d = 0.0
    foreach ($t in @($Inventory.TablesWithData)) {
        $totalGb30d += [double](Get-PropOrDefault $t 'BillableLast30d' 0)
    }
    if ($totalGb30d -le 0) { return $null }
    $dailyAvg = $totalGb30d / 30.0

    if (-not $Inventory.CommitmentTiers) { return $null }
    $rungs = @($Inventory.CommitmentTiers.rungsGbPerDay)
    $next = $rungs | Where-Object { $_ -le $dailyAvg } | Select-Object -Last 1
    if ($next) {
        return New-Finding -Evidence "30-day average ingest is ~$([math]::Round($dailyAvg,1)) GB/day on PerGB2018; $next GB/day commitment tier is a candidate." -Detail @{ DailyAvgGb = $dailyAvg; NextRung = $next }
    }
    return $null
}

# ------------------------------------------------------------
# SENT-016 — High-volume table candidate for Basic/Auxiliary
# ------------------------------------------------------------
function Test-HighVolumeTablePlanCandidate {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    $analytics = @{}
    foreach ($t in @($Inventory.WorkspaceTables)) {
        $name = Get-PropOrDefault $t 'name' ''
        $plan = Get-PropOrDefault $t 'properties.plan' ''
        if ($name -and $plan -eq 'Analytics') { $analytics[$name] = $true }
    }
    $candidates = @($Inventory.TablesWithData | Where-Object {
        ([double](Get-PropOrDefault $_ 'BillableLast30d' 0)) -gt 50.0 -and
        $analytics.ContainsKey((Get-PropOrDefault $_ 'DataType' ''))
    })
    if ($candidates.Count -gt 0) {
        $names = ($candidates | Select-Object -ExpandProperty DataType) -join ', '
        return New-Finding -Evidence "Analytics-plan tables > 50 GB/30d that are Basic/Auxiliary candidates: $names." -Detail @{ Tables = $names }
    }
    return $null
}

# ------------------------------------------------------------
# SENT-017 — Long retention on Analytics rather than archive
# ------------------------------------------------------------
function Test-RetentionOverArchive {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    $bad = @($Inventory.WorkspaceTables | Where-Object {
        $r = [int](Get-PropOrDefault $_ 'properties.retentionInDays' 0)
        $r -gt 90
    })
    if ($bad.Count -gt 0) {
        return New-Finding -Evidence "$($bad.Count) table(s) have interactive retention > 90d. Consider lowering retentionInDays and using totalRetentionInDays for archive." -Detail @{ Count = $bad.Count }
    }
    return $null
}

# ------------------------------------------------------------
# SENT-018 — Dedicated cluster candidate
# ------------------------------------------------------------
function Test-DedicatedClusterCandidate {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    if ($Inventory.DedicatedCluster) { return $null }
    $totalGb30d = 0.0
    foreach ($t in @($Inventory.TablesWithData)) {
        $totalGb30d += [double](Get-PropOrDefault $t 'BillableLast30d' 0)
    }
    $dailyAvg = $totalGb30d / 30.0
    if ($dailyAvg -gt 500.0) {
        return New-Finding -Evidence "Average ingest ~$([math]::Round($dailyAvg,1)) GB/day with no dedicated cluster — cluster offers cluster-level CR pricing, CMK, and AZ." -Detail @{ DailyAvgGb = $dailyAvg }
    }
    return $null
}

# ------------------------------------------------------------
# SENT-019 — Sentinel benefit not detected
# ------------------------------------------------------------
function Test-SentinelBenefitApplied {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    if (-not $Inventory.SentinelBenefitTables) { return $null }
    $eligible = $Inventory.SentinelBenefitTables.tables
    $billableSecurity = @($Inventory.TablesWithData | Where-Object {
        ($eligible -contains (Get-PropOrDefault $_ 'DataType' '')) -and
        ([double](Get-PropOrDefault $_ 'BillableLast30d' 0) -gt 0)
    })
    if ($billableSecurity.Count -gt 0) {
        $names = ($billableSecurity | Select-Object -ExpandProperty DataType) -join ', '
        return New-Finding -Evidence "Eligible security tables with non-zero billable ingest in 30d: $names. If Defender plans are in force the benefit may not be applied." -Detail @{ Tables = $names }
    }
    return $null
}

# ------------------------------------------------------------
# SENT-020 — Workspace replication disabled
# ------------------------------------------------------------
function Test-ReplicationEnabled {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    $enabled = Get-PropOrDefault $Inventory.Workspace 'properties.replication.enabled' $false
    if (-not $enabled) {
        return New-Finding -Evidence 'Workspace replication is disabled.'
    }
    return $null
}

# ------------------------------------------------------------
# SENT-021 — Public network access enabled
# ------------------------------------------------------------
function Test-PublicNetworkAccessDisabled {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    $ingest = Get-PropOrDefault $Inventory.Workspace 'properties.publicNetworkAccessForIngestion' 'Enabled'
    $query  = Get-PropOrDefault $Inventory.Workspace 'properties.publicNetworkAccessForQuery'     'Enabled'
    if ($ingest -eq 'Enabled' -or $query -eq 'Enabled') {
        return New-Finding -Evidence "Public network access enabled (Ingestion=$ingest, Query=$query)." -Detail @{ Ingestion = $ingest; Query = $query }
    }
    return $null
}

# ------------------------------------------------------------
# SENT-022 — Resource providers registered
# ------------------------------------------------------------
function Test-ResourceProvidersRegistered {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    $required = @('Microsoft.SecurityInsights','Microsoft.OperationalInsights','Microsoft.Insights')
    $bad = @($Inventory.ResourceProviders | Where-Object {
        $name = Get-PropOrDefault $_ 'ProviderNamespace' ''
        $state = Get-PropOrDefault $_ 'RegistrationState' ''
        ($required -contains $name) -and ($state -ne 'Registered')
    })
    if ($bad.Count -gt 0) {
        $names = ($bad | Select-Object -ExpandProperty ProviderNamespace) -join ', '
        return New-Finding -Evidence "Resource provider(s) not registered: $names." -Detail @{ Providers = $names }
    }
    return $null
}

# ------------------------------------------------------------
# SENT-023 — Data Lake mirroring candidate
# ------------------------------------------------------------
function Test-DataLakeMirroringCandidate {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    # Heuristic — long-tail tables (>30 GB/30d, retention > 90d, plan = Analytics).
    $analyticsLongRetention = @($Inventory.WorkspaceTables | Where-Object {
        (Get-PropOrDefault $_ 'properties.plan' '') -eq 'Analytics' -and
        [int](Get-PropOrDefault $_ 'properties.totalRetentionInDays' 0) -gt 365
    })
    if ($analyticsLongRetention.Count -gt 0) {
        return New-Finding -Evidence "$($analyticsLongRetention.Count) Analytics-plan table(s) with > 365d total retention — Data Lake mirroring candidates." -Detail @{ Count = $analyticsLongRetention.Count }
    }
    return $null
}

# ------------------------------------------------------------
# SENT-024 — disableLocalAuth
# ------------------------------------------------------------
function Test-DisableLocalAuth {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    $disabled = Get-PropOrDefault $Inventory.Workspace 'properties.features.disableLocalAuth' $false
    if (-not $disabled) {
        return New-Finding -Evidence 'features.disableLocalAuth is false — workspace shared keys are accepted for ingestion.'
    }
    return $null
}

# ------------------------------------------------------------
# SENT-025 — Access mode consistency
# ------------------------------------------------------------
function Test-AccessModeConsistent {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    # Informational — surface the flag value so the reviewer can confirm it matches intent.
    $flag = Get-PropOrDefault $Inventory.Workspace 'properties.features.enableLogAccessUsingOnlyResourcePermissions' $null
    if ($null -eq $flag) {
        return New-Finding -Evidence 'enableLogAccessUsingOnlyResourcePermissions is unset — confirm whether resource-context or workspace-context access is intended.'
    }
    return $null
}

# ------------------------------------------------------------
# SENT-026 — Silent tables (had data, none last 7d)
# ------------------------------------------------------------
function Test-SilentTables {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    if (-not $Inventory.TablesWithData) { return $null }
    $silent = @($Inventory.TablesWithData | Where-Object {
        $last7 = [double](Get-PropOrDefault $_ 'BillableLast7d' 0)
        $last90 = [double](Get-PropOrDefault $_ 'BillableLast90d' 0)
        ($last7 -eq 0) -and ($last90 -gt 0)
    })
    if ($silent.Count -gt 0) {
        $names = ($silent | Select-Object -ExpandProperty DataType) -join ', '
        return New-Finding -Evidence "Silent table(s) (data in 90d but none in 7d): $names." -Detail @{ Tables = $names }
    }
    return $null
}

# ------------------------------------------------------------
# SENT-027 — Orphan tables (schema, no data 90d)
# ------------------------------------------------------------
function Test-OrphanTables {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    if (-not $Inventory.WorkspaceTables -or -not $Inventory.TablesWithData) { return $null }
    $populated = @{}
    foreach ($t in $Inventory.TablesWithData) {
        $populated[(Get-PropOrDefault $t 'DataType' '')] = $true
    }
    $orphans = @($Inventory.WorkspaceTables | Where-Object {
        $name = Get-PropOrDefault $_ 'name' ''
        $type = Get-PropOrDefault $_ 'properties.schema.tableType' ''
        # Custom (_CL) tables only. Microsoft pre-defined tables without data
        # are part of every workspace's catalogue (~750 of them on a typical
        # Sentinel workspace) and aren't orphans — they're 'sources we
        # haven't onboarded'. Custom tables, on the other hand, were
        # explicitly created to receive data; if none has arrived in 90d,
        # the source is broken or the table should be deleted.
        $type -eq 'CustomLog' -and -not $populated.ContainsKey($name)
    })
    if ($orphans.Count -gt 0) {
        return New-Finding -Evidence "$($orphans.Count) table(s) have a schema but no data in 90d." -Detail @{ Count = $orphans.Count }
    }
    return $null
}

# ------------------------------------------------------------
# SENT-028 — Connector connected but target table has no recent data
# ------------------------------------------------------------
function Test-ConnectorTableMismatch {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    if (-not $Inventory.DataConnectors -or -not $Inventory.TablesWithData) { return $null }
    # Build per-table 24h activity map.
    $active24h = @{}
    foreach ($t in $Inventory.TablesWithData) {
        if ([double](Get-PropOrDefault $t 'BillableLast24h' 0) -gt 0) {
            $active24h[(Get-PropOrDefault $t 'DataType' '')] = $true
        }
    }
    # Connector → expected target tables. For now this is a coarse heuristic — kind name
    # → known table list. Refined per connector by maintaining a lookup elsewhere.
    $kindToTables = @{
        'AzureActiveDirectory'                       = @('SigninLogs','AuditLogs','AADNonInteractiveUserSignInLogs')
        'Office365'                                  = @('OfficeActivity')
        'AzureSecurityCenter'                        = @('SecurityAlert')
        'MicrosoftDefenderAdvancedThreatProtection'  = @('SecurityAlert')
        'MicrosoftThreatProtection'                  = @('SecurityIncident','SecurityAlert')
    }
    $bad = @()
    foreach ($c in $Inventory.DataConnectors) {
        $kind = Get-PropOrDefault $c 'kind' ''
        if (-not $kindToTables.ContainsKey($kind)) { continue }
        foreach ($expected in $kindToTables[$kind]) {
            if (-not $active24h.ContainsKey($expected)) { $bad += "$kind→$expected" }
        }
    }
    if ($bad.Count -gt 0) {
        return New-Finding -Evidence "Connector(s) reporting connected with no recent data in target table(s): $($bad -join '; ')." -Detail @{ Mismatches = $bad }
    }
    return $null
}

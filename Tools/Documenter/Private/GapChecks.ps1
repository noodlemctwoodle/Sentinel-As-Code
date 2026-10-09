#Requires -Version 7.2

<#
.SYNOPSIS
    Gap-analysis check functions, one per row in best-practices.json.

.DESCRIPTION
    Each function takes a single $Inventory parameter, the in-memory object built by
    Get-SentinelGap from the _raw/ JSON files, and returns either:

      $null                   : no gap detected (rule passes)
      [pscustomobject]@{...}  : a finding with Evidence + Detail fields

    Adding a new rule is a two-step process: drop a Test-* function in this file, add a
    row to best-practices.json that references it by name. The engine wires the rest.

.NOTES
    File:           Tools/Documenter/Private/GapChecks.ps1
    Repository:     Sentinel-As-Code
    Author:         noodlemctwoodle
    Website:        https://sentinel.blog
    Created:        2026-05-06
    Version:        0.2.0
    Last Updated:   2026-10-09
    Component:      Sentinel Documenter, Gap Engine
    Requires:       PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on each Test-* function's own help block.
#>

Set-StrictMode -Version Latest

# Helper, produces a Finding object with consistent shape.
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

# Helper, returns a property if it exists, else default. Sentinel/LA REST occasionally
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
# SENT-001, Daily cap not configured
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
# SENT-002, Workspace default retention < 90d
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
# SENT-003, High-volume table on Analytics with no transform
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
# SENT-004, Recommended connectors not deployed
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
# SENT-005, UEBA disabled
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
# SENT-006, MITRE tactic with zero enabled rules
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
# SENT-007, Rules disabled or in error
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
# SENT-008, High-severity templates not deployed
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
# SENT-009, Owner/Contributor at workspace scope
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
# SENT-010, Diagnostic settings not configured
# ------------------------------------------------------------
function Test-DiagnosticSettingsConfigured {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    if (-not $Inventory.DiagnosticSettings -or @($Inventory.DiagnosticSettings).Count -eq 0) {
        return New-Finding -Evidence 'No diagnostic settings configured on the Log Analytics workspace.'
    }
    return $null
}

# ------------------------------------------------------------
# SENT-011, Playbook MI lacks Sentinel Responder role
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
# SENT-012, DCR transform missing on noisy custom table
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
# SENT-013, Content Hub solution updates available
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
# SENT-014, Sentinel still on Azure portal (info-only)
# ------------------------------------------------------------
function Test-OnboardedToDefender {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    # The defender-onboarding state is workspace-specific and exposed via a separate REST
    # surface that may not be in scope. Until we wire that detection, surface the deadline
    # universally as an Info finding so it appears in every report.
    return New-Finding -Evidence 'Sentinel in the Azure portal retires 2027-03-31. Plan the migration to the unified Defender XDR experience.' -Detail @{ Deadline = '2027-03-31' }
}

# ------------------------------------------------------------
# SENT-015, Commitment-tier opportunity
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
# SENT-016, High-volume table candidate for Basic/Auxiliary
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
# SENT-017, Long retention on Analytics rather than archive
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
# SENT-018, Dedicated cluster candidate
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
        return New-Finding -Evidence "Average ingest ~$([math]::Round($dailyAvg,1)) GB/day with no dedicated cluster, cluster offers cluster-level CR pricing, CMK, and AZ." -Detail @{ DailyAvgGb = $dailyAvg }
    }
    return $null
}

# ------------------------------------------------------------
# SENT-019, Sentinel benefit not detected
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
# SENT-020, Workspace replication disabled
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
# SENT-021, Public network access enabled
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
# SENT-022, Resource providers registered
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
# SENT-023, Data Lake mirroring candidate
# ------------------------------------------------------------
function Test-DataLakeMirroringCandidate {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    # Heuristic, long-tail tables (>30 GB/30d, retention > 90d, plan = Analytics).
    $analyticsLongRetention = @($Inventory.WorkspaceTables | Where-Object {
        (Get-PropOrDefault $_ 'properties.plan' '') -eq 'Analytics' -and
        [int](Get-PropOrDefault $_ 'properties.totalRetentionInDays' 0) -gt 365
    })
    if ($analyticsLongRetention.Count -gt 0) {
        return New-Finding -Evidence "$($analyticsLongRetention.Count) Analytics-plan table(s) with > 365d total retention, Data Lake mirroring candidates." -Detail @{ Count = $analyticsLongRetention.Count }
    }
    return $null
}

# ------------------------------------------------------------
# SENT-024, disableLocalAuth
# ------------------------------------------------------------
function Test-DisableLocalAuth {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    $disabled = Get-PropOrDefault $Inventory.Workspace 'properties.features.disableLocalAuth' $false
    if (-not $disabled) {
        return New-Finding -Evidence 'features.disableLocalAuth is false, workspace shared keys are accepted for ingestion.'
    }
    return $null
}

# ------------------------------------------------------------
# SENT-025, Access mode consistency
# ------------------------------------------------------------
function Test-AccessModeConsistent {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    # Informational, surface the flag value so the reviewer can confirm it matches intent.
    $flag = Get-PropOrDefault $Inventory.Workspace 'properties.features.enableLogAccessUsingOnlyResourcePermissions' $null
    if ($null -eq $flag) {
        return New-Finding -Evidence 'enableLogAccessUsingOnlyResourcePermissions is unset, confirm whether resource-context or workspace-context access is intended.'
    }
    return $null
}

# ------------------------------------------------------------
# SENT-026, Silent tables (had data, none last 7d)
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
# SENT-027, Orphan tables (schema, no data 90d)
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
        # Sentinel workspace) and aren't orphans, they're 'sources we
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
# Helper, does a TablesWithData record claim non-zero billable ingest in
# the last 30 days? Returns the GB value as a [double], or 0 when missing.
# ------------------------------------------------------------
function _GetBillable30d {
    param([object]$Row)
    $v = Get-PropOrDefault $Row 'BillableLast30d' 0
    if ($null -eq $v) { return 0.0 }
    $d = 0.0
    if ([double]::TryParse([string]$v, [ref]$d)) { return $d }
    return 0.0
}

# ------------------------------------------------------------
# SENT-028, Connector connected but target table has no recent data
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
    # Connector → expected target tables. For now this is a coarse heuristic, kind name
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

# ------------------------------------------------------------
# SENT-029, Incident MTTR above 24h
# ------------------------------------------------------------
function Test-IncidentMttrThreshold {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    if (-not $Inventory.IncidentsMttr -or @($Inventory.IncidentsMttr).Count -eq 0) { return $null }
    $row = $Inventory.IncidentsMttr[0]
    $closed = [int](Get-PropOrDefault $row 'ClosedCount' 0)
    if ($closed -eq 0) { return $null }
    $mttrRaw = Get-PropOrDefault $row 'MTTRMinutes' $null
    $mttr = 0.0
    if (-not [double]::TryParse([string]$mttrRaw, [ref]$mttr)) { return $null }
    if ($mttr -le 1440.0) { return $null }
    $hours = [math]::Round($mttr / 60.0, 1)
    return New-Finding -Evidence "MTTR over the last 30 days is $hours hours across $closed closed incident(s); SOC target is <= 24h." -Detail @{ MttrHours = $hours; ClosedCount = $closed }
}

# ------------------------------------------------------------
# SENT-030, Majority of incidents closed without ever being acknowledged
# ------------------------------------------------------------
function Test-IncidentClosedWithoutAcknowledgement {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    if (-not $Inventory.IncidentsMttr -or @($Inventory.IncidentsMttr).Count -eq 0) { return $null }
    $row = $Inventory.IncidentsMttr[0]
    $closed = [int](Get-PropOrDefault $row 'ClosedCount' 0)
    # The AcknowledgedCount column was added by a recent fix; on older
    # capture files it isn't present and the check has nothing to evaluate.
    if ($row.PSObject.Properties.Name -notcontains 'AcknowledgedCount') { return $null }
    $ack = [int](Get-PropOrDefault $row 'AcknowledgedCount' 0)
    if ($closed -lt 10) { return $null }            # statistical floor, small samples lie
    $unack = $closed - $ack
    $ratio = $unack / [double]$closed
    if ($ratio -le 0.5) { return $null }
    return New-Finding -Evidence "$unack of $closed closed incidents ($([math]::Round($ratio*100,0))%) never reached an acknowledged state. Automation is auto-closing without analyst review, or analytics rules are flooding the queue." -Detail @{ Closed = $closed; Acknowledged = $ack; Unacknowledged = $unack }
}

# ------------------------------------------------------------
# SENT-031, Mouldy rules, enabled, untouched > 12 months
# ------------------------------------------------------------
function Test-MouldyAnalyticsRules {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    if (-not $Inventory.AlertRules) { return $null }
    $cutoff = (Get-Date).ToUniversalTime().AddDays(-365)
    # ConvertFrom-Json auto-deserialises ISO-8601 timestamps to [datetime];
    # round-tripping via [string] then TryParse uses the current culture and
    # can drop the round-trip on en-GB machines. Cast directly with a try
    # block so both [string] and [datetime] inputs work identically.
    $mouldy = @($Inventory.AlertRules | Where-Object {
        $kind = Get-PropOrDefault $_ 'kind' ''
        $enabled = Get-PropOrDefault $_ 'properties.enabled' $false
        $lm = Get-PropOrDefault $_ 'properties.lastModifiedUtc' $null
        $parsed = [datetime]::MinValue
        $tsValid = $false
        if ($lm) { try { $parsed = [datetime]$lm; $tsValid = $true } catch {} }
        ($kind -in @('Scheduled','NRT')) -and $enabled -and $tsValid -and ($parsed.ToUniversalTime() -lt $cutoff)
    })
    if ($mouldy.Count -eq 0) { return $null }
    $names = ($mouldy | Select-Object -First 5 | ForEach-Object { Get-PropOrDefault $_ 'properties.displayName' '?' }) -join '; '
    $suffix = if ($mouldy.Count -gt 5) { " (+ $($mouldy.Count - 5) more)" } else { '' }
    return New-Finding -Evidence "$($mouldy.Count) enabled Scheduled/NRT rule(s) not modified in over 12 months: $names$suffix." -Detail @{ Count = $mouldy.Count }
}

# ------------------------------------------------------------
# SENT-032, Deployed rule's templateVersion lags the latest template
# ------------------------------------------------------------
function Test-AnalyticsRuleTemplateDrift {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    if (-not $Inventory.AlertRules -or -not $Inventory.AlertRuleTemplates) { return $null }
    $latestByTemplate = @{}
    foreach ($t in $Inventory.AlertRuleTemplates) {
        $tname = Get-PropOrDefault $t 'name' ''
        $v = Get-PropOrDefault $t 'properties.version' $null
        if ($tname -and $v) { $latestByTemplate[$tname] = [string]$v }
    }
    if ($latestByTemplate.Count -eq 0) { return $null }
    $drifted = @()
    foreach ($r in $Inventory.AlertRules) {
        $tplName = Get-PropOrDefault $r 'properties.alertRuleTemplateName' $null
        if (-not $tplName) { continue }
        if (-not $latestByTemplate.ContainsKey($tplName)) { continue }
        $deployed = Get-PropOrDefault $r 'properties.templateVersion' $null
        if (-not $deployed) { continue }
        if ([string]$deployed -ne $latestByTemplate[$tplName]) {
            $drifted += [pscustomobject]@{
                Name     = Get-PropOrDefault $r 'properties.displayName' '?'
                Deployed = [string]$deployed
                Latest   = $latestByTemplate[$tplName]
            }
        }
    }
    if ($drifted.Count -eq 0) { return $null }
    $sample = ($drifted | Select-Object -First 5 | ForEach-Object { "$($_.Name) ($($_.Deployed)→$($_.Latest))" }) -join '; '
    $suffix = if ($drifted.Count -gt 5) { " (+ $($drifted.Count - 5) more)" } else { '' }
    return New-Finding -Evidence "$($drifted.Count) deployed rule(s) lag the latest template version: $sample$suffix." -Detail @{ Count = $drifted.Count }
}

# ------------------------------------------------------------
# SENT-033, Single rule producing > 30% of alert volume
# ------------------------------------------------------------
function Test-DominantNoisyRule {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    if (-not $Inventory.AnalyticsRuleVolumes -or @($Inventory.AnalyticsRuleVolumes).Count -eq 0) { return $null }
    $rows = @($Inventory.AnalyticsRuleVolumes)
    $totalAlerts = ($rows | ForEach-Object { [double](Get-PropOrDefault $_ 'Alerts' 0) } | Measure-Object -Sum).Sum
    if (-not $totalAlerts -or $totalAlerts -lt 100) { return $null }   # too quiet to draw conclusions
    $top = $rows | Sort-Object -Property @{ Expression = { [double](Get-PropOrDefault $_ 'Alerts' 0) } } -Descending | Select-Object -First 1
    $topAlerts = [double](Get-PropOrDefault $top 'Alerts' 0)
    $ratio = $topAlerts / [double]$totalAlerts
    if ($ratio -le 0.30) { return $null }
    $name = Get-PropOrDefault $top 'AlertName' '?'
    return New-Finding -Evidence "Rule `"$name`" produced $([int]$topAlerts) of $([int]$totalAlerts) alerts in 30d ($([math]::Round($ratio*100,0))%), tuning candidate." -Detail @{ AlertName = $name; Alerts = [int]$topAlerts; Total = [int]$totalAlerts; Ratio = $ratio }
}

# ------------------------------------------------------------
# SENT-034, No automation rules defined
# ------------------------------------------------------------
function Test-AutomationRulesPresent {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    $count = @($Inventory.AutomationRules).Count
    if ($count -gt 0) { return $null }
    return New-Finding -Evidence 'No automation rules defined, every incident requires manual triage.'
}

# ------------------------------------------------------------
# SENT-035, Enabled rule with zero alerts in 90d
# ------------------------------------------------------------
function Test-DeadAnalyticsRule {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    if (-not $Inventory.AlertRules -or -not $Inventory.AnalyticsRuleVolumes) { return $null }
    # Volumes capture is over 30d. Project the noisy-rule set into a name lookup
    # then surface enabled Scheduled/NRT rules whose displayName is absent
    # from it, they produced no alerts in the window.
    $noisy = @{}
    foreach ($v in $Inventory.AnalyticsRuleVolumes) {
        $n = Get-PropOrDefault $v 'AlertName' ''
        if ($n) { $noisy[$n] = $true }
    }
    if ($noisy.Count -eq 0) { return $null }    # no volumes -> no signal
    $dead = @($Inventory.AlertRules | Where-Object {
        $kind = Get-PropOrDefault $_ 'kind' ''
        $enabled = Get-PropOrDefault $_ 'properties.enabled' $false
        $name = Get-PropOrDefault $_ 'properties.displayName' ''
        ($kind -in @('Scheduled','NRT')) -and $enabled -and $name -and (-not $noisy.ContainsKey($name))
    })
    if ($dead.Count -eq 0) { return $null }
    $sample = ($dead | Select-Object -First 5 | ForEach-Object { Get-PropOrDefault $_ 'properties.displayName' '?' }) -join '; '
    $suffix = if ($dead.Count -gt 5) { " (+ $($dead.Count - 5) more)" } else { '' }
    return New-Finding -Evidence "$($dead.Count) enabled Scheduled/NRT rule(s) produced zero alerts in 30 days: $sample$suffix." -Detail @{ Count = $dead.Count }
}

# ------------------------------------------------------------
# SENT-039, Service principal with Owner/Contributor at workspace scope
# ------------------------------------------------------------
function Test-ServicePrincipalOverPrivileged {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    if (-not $Inventory.RbacWorkspace) { return $null }
    $bad = @($Inventory.RbacWorkspace | Where-Object {
        $role = Get-PropOrDefault $_ 'RoleDefinitionName' ''
        $type = Get-PropOrDefault $_ 'ObjectType' ''
        ($role -in @('Owner','Contributor')) -and ($type -eq 'ServicePrincipal')
    })
    if ($bad.Count -eq 0) { return $null }
    $names = ($bad | Select-Object -First 5 | ForEach-Object { Get-PropOrDefault $_ 'DisplayName' '?' }) -join '; '
    $suffix = if ($bad.Count -gt 5) { " (+ $($bad.Count - 5) more)" } else { '' }
    return New-Finding -Evidence "$($bad.Count) service principal(s) hold Owner or Contributor at workspace scope: $names$suffix." -Detail @{ Count = $bad.Count }
}

# ------------------------------------------------------------
# SENT-040, Zero Microsoft Sentinel Responder assignments
# ------------------------------------------------------------
function Test-ResponderRoleAssigned {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    if (-not $Inventory.RbacWorkspace) { return $null }
    $hasResponder = @($Inventory.RbacWorkspace | Where-Object {
        (Get-PropOrDefault $_ 'RoleDefinitionName' '') -eq 'Microsoft Sentinel Responder'
    }).Count -gt 0
    if ($hasResponder) { return $null }
    return New-Finding -Evidence 'No identity holds the Microsoft Sentinel Responder role at workspace scope. Analysts cannot act on incidents through least-privilege access.'
}

# ------------------------------------------------------------
# SENT-042, No deletion-protection lock on the workspace
# ------------------------------------------------------------
function Test-WorkspaceLockPresent {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    $locks = @($Inventory.WorkspaceLocks)
    $relevant = @($locks | Where-Object {
        $level = Get-PropOrDefault $_ 'properties.level' ''
        $level -in @('CanNotDelete','ReadOnly')
    })
    if ($relevant.Count -gt 0) { return $null }
    return New-Finding -Evidence 'No CanNotDelete or ReadOnly lock on the workspace. Accidental or malicious deletion would lose all detection rules, watchlists, hunting queries, and historical incident data.'
}

# ------------------------------------------------------------
# Data-routing helper, CEF / Syslog / Windows split-opportunity threshold
# ------------------------------------------------------------
# All four data-routing rules use the same pattern: "is table X carrying
# enough volume to make the engineering effort to split worth it?". Five GB
# over the 30-day window (~150 GB/30d) is the conservative default, below
# that, the per-month saving from splitting probably can't pay for the DCR
# authoring time.
$script:DataRoutingSplitThresholdGb30d = 150.0

# ------------------------------------------------------------
# SENT-043, CommonSecurityLog volume warrants a vendor _CL split
# ------------------------------------------------------------
function Test-CefSplitOpportunity {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    $cef = @($Inventory.TablesWithData | Where-Object {
        (Get-PropOrDefault $_ 'DataType' '') -eq 'CommonSecurityLog'
    } | Select-Object -First 1)
    if ($cef.Count -eq 0) { return $null }
    $gb30 = _GetBillable30d $cef[0]
    if ($gb30 -lt $script:DataRoutingSplitThresholdGb30d) { return $null }
    return New-Finding -Evidence "CommonSecurityLog ingested $([math]::Round($gb30,1)) GB in the last 30 days at the Sentinel security-data rate, routine vendor records could split to a `<Vendor>_CL` custom table via a DCR filter+split transformation." -Detail @{ Gb30d = $gb30 }
}

# ------------------------------------------------------------
# SENT-044, Syslog volume warrants a facility-based DCR filter or _CL split
# ------------------------------------------------------------
function Test-SyslogSplitOpportunity {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    $sys = @($Inventory.TablesWithData | Where-Object {
        (Get-PropOrDefault $_ 'DataType' '') -eq 'Syslog'
    } | Select-Object -First 1)
    if ($sys.Count -eq 0) { return $null }
    $gb30 = _GetBillable30d $sys[0]
    if ($gb30 -lt $script:DataRoutingSplitThresholdGb30d) { return $null }
    return New-Finding -Evidence "Syslog ingested $([math]::Round($gb30,1)) GB in the last 30 days, narrow the AMA DCR's facilityNames + logLevels to security-relevant facilities and route the rest to a custom _CL table at LA rates." -Detail @{ Gb30d = $gb30 }
}

# ------------------------------------------------------------
# SENT-045, SecurityEvent / WindowsEvent XPath filter opportunity
# ------------------------------------------------------------
function Test-WindowsEventXPathFilterOpportunity {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    # 5 GB / day across SecurityEvent + WindowsEvent is the trigger, the
    # AMA DCRs that ship Microsoft's own SecurityEvent collection ('All
    # Events') easily clear that on a domain controller, and the XPath
    # change is a documented, low-risk DCR edit.
    $tables = @('SecurityEvent','WindowsEvent','Event')
    $totalGb30 = 0.0
    foreach ($t in @($Inventory.TablesWithData)) {
        if ($tables -contains (Get-PropOrDefault $t 'DataType' '')) {
            $totalGb30 += _GetBillable30d $t
        }
    }
    if ($totalGb30 -lt $script:DataRoutingSplitThresholdGb30d) { return $null }
    return New-Finding -Evidence "SecurityEvent/WindowsEvent ingested $([math]::Round($totalGb30,1)) GB in the last 30 days, typical AMA collection ships every Event ID. Add an XPath filter to drop 4624/4634/4672/5379 noise at the DCR." -Detail @{ Gb30d = $totalGb30 }
}

# ------------------------------------------------------------
# SENT-046, AzureDiagnostics carries multiple resource providers
# ------------------------------------------------------------
function Test-AzureDiagnosticsResourceSpecific {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    $ad = @($Inventory.TablesWithData | Where-Object {
        (Get-PropOrDefault $_ 'DataType' '') -eq 'AzureDiagnostics'
    } | Select-Object -First 1)
    if ($ad.Count -eq 0) { return $null }
    $gb30 = _GetBillable30d $ad[0]
    if ($gb30 -lt 10.0) { return $null }    # smaller threshold, even 10 GB across many RPs is messy
    # We don't know per-RP breakdown from tables-with-data alone (the
    # AzureDiagnostics rendering is summarised in 14-coverage-breakdowns.md
    # but isn't a separate _raw capture). Flag based on volume alone, the
    # remediation is still correct: switch any RP that has a dedicated
    # resource-specific table.
    return New-Finding -Evidence "AzureDiagnostics ingested $([math]::Round($gb30,1)) GB in the last 30 days. Resource-specific tables are cheaper, faster to query, and have stable schemas, review diagnostic settings and switch each resource type to dedicated table mode." -Detail @{ Gb30d = $gb30 }
}

# ------------------------------------------------------------
# SENT-047, CLv1 (HTTP Data Collector API) custom log tables still in use
# ------------------------------------------------------------
function Test-CustomLogsV1Migration {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    if (-not $Inventory.WorkspaceTables -or -not $Inventory.TablesWithData -or -not $Inventory.Dcrs) { return $null }

    # Project the set of _CL tables that have any DCR feeding them. A DCR's
    # dataFlows[].outputStream is shaped "Custom-<TableName>_CL" when it
    # writes into a custom table; index by the bare table name.
    $tablesWithDcr = @{}
    foreach ($dcr in $Inventory.Dcrs) {
        $flows = Get-PropOrDefault $dcr 'properties.dataFlows' @()
        foreach ($f in @($flows)) {
            $stream = Get-PropOrDefault $f 'outputStream' ''
            if ($stream -match '^Custom-(.+)$') {
                $tablesWithDcr[$matches[1]] = $true
            }
        }
    }

    # Project _CL tables that have data in the last 90 days.
    $active = @{}
    foreach ($t in $Inventory.TablesWithData) {
        $name = Get-PropOrDefault $t 'DataType' ''
        $gb90 = [double](Get-PropOrDefault $t 'BillableLast90d' 0)
        if ($name -and $gb90 -gt 0) { $active[$name] = $true }
    }

    # Filter to genuine custom-log tables. tableType alone is unreliable, 
    # some workspaces report AzureDiagnostics and other Microsoft service
    # tables as 'CustomLog' when custom diagnostic settings have been
    # written to them. The `_CL` name suffix is enforced at table creation
    # and is the authoritative custom-table marker.
    $clv1 = @($Inventory.WorkspaceTables | Where-Object {
        $name = Get-PropOrDefault $_ 'name' ''
        $type = Get-PropOrDefault $_ 'properties.schema.tableType' ''
        ($type -eq 'CustomLog') -and ($name -like '*_CL') -and $active.ContainsKey($name) -and (-not $tablesWithDcr.ContainsKey($name))
    })
    if ($clv1.Count -eq 0) { return $null }
    $names = ($clv1 | Select-Object -First 8 | ForEach-Object { Get-PropOrDefault $_ 'name' '?' }) -join ', '
    $suffix = if ($clv1.Count -gt 8) { " (+ $($clv1.Count - 8) more)" } else { '' }
    return New-Finding -Evidence "$($clv1.Count) custom log table(s) receive data but no DCR feeds them, likely still using the HTTP Data Collector API (CLv1). Affected: $names$suffix. Retirement is 2026-09-14." -Detail @{ Count = $clv1.Count }
}

# ------------------------------------------------------------
# SENT-048, MMA / OMS / Log Analytics agent still heartbeating
# ------------------------------------------------------------
function Test-MmaAgentStillHeartbeating {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    if (-not $Inventory.AmaMmaMigration -or @($Inventory.AmaMmaMigration).Count -eq 0) { return $null }
    $mmaTotal = 0
    foreach ($row in $Inventory.AmaMmaMigration) {
        $mma = [int](Get-PropOrDefault $row 'MMACount' 0)
        if ($mma -gt 0) { $mmaTotal += $mma }
    }
    if ($mmaTotal -eq 0) { return $null }
    return New-Finding -Evidence "$mmaTotal machine(s) still heartbeating via the legacy Log Analytics agent (MMA / OMS). MMA retired 2024-08-31; ingestion is degraded after 2025-02-01." -Detail @{ MmaCount = $mmaTotal }
}

# ------------------------------------------------------------
# SENT-049, Legacy ThreatIntelligenceIndicator table still in use
# ------------------------------------------------------------
function Test-LegacyThreatIntelligenceTable {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    if (-not $Inventory.TablesWithData) { return $null }
    $legacy = @($Inventory.TablesWithData | Where-Object {
        (Get-PropOrDefault $_ 'DataType' '') -eq 'ThreatIntelligenceIndicator' -and
        [double](Get-PropOrDefault $_ 'BillableLast30d' 0) -gt 0
    } | Select-Object -First 1)
    if ($legacy.Count -eq 0) { return $null }
    $gb30 = [double](Get-PropOrDefault $legacy[0] 'BillableLast30d' 0)
    # Detect whether the workspace has ALSO started receiving into the new
    # ThreatIntelIndicators table, if yes the finding evidence calls out
    # that the migration is half done; if no, fresh ingestion is broken.
    $newPresent = @($Inventory.TablesWithData | Where-Object {
        (Get-PropOrDefault $_ 'DataType' '') -eq 'ThreatIntelIndicators' -and
        [double](Get-PropOrDefault $_ 'BillableLast30d' 0) -gt 0
    }).Count -gt 0
    $statusNote = if ($newPresent) {
        'New ThreatIntelIndicators table is also active, partial migration; ensure all detections, hunting queries and workbooks read from the new tables.'
    } else {
        'No data observed in the new ThreatIntelIndicators / ThreatIntelObjects tables, TI ingestion may be broken since the 2025-07-31 cutoff.'
    }
    return New-Finding -Evidence "ThreatIntelligenceIndicator (legacy) carries $([math]::Round($gb30,3)) GB in the last 30 days. $statusNote" -Detail @{ LegacyGb30d = $gb30; NewTablePresent = $newPresent }
}

# ============================================================
# v2.2 rules, from the Sentinel health-check script contributed to the
# project: detection effectiveness, table-to-rule mapping, run health,
# hunting activity and threat-intelligence feed coverage. They read the
# collector files added at the same time (rule-table-references,
# rule-effectiveness, playbook-runs, hunts, azure-diagnostics-categories)
# plus the extended incidents-summary and tables-with-data captures.
#
# KQL result cells arrive as strings from Invoke-AzOperationalInsightsQuery
# and as typed values from fixture files, so every numeric read goes
# through _ToInt / _ToDouble and every flag through _ToBool.
# ============================================================

function _ToInt {
    param([object]$Value)
    if ($null -eq $Value) { return 0 }
    $d = 0.0
    if ([double]::TryParse([string]$Value, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { return [int][math]::Round($d) }
    return 0
}

function _ToDouble {
    param([object]$Value)
    if ($null -eq $Value) { return 0.0 }
    $d = 0.0
    if ([double]::TryParse([string]$Value, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { return $d }
    return 0.0
}

function _ToBool {
    param([object]$Value)
    if ($null -eq $Value) { return $false }
    if ($Value -is [bool]) { return $Value }
    return ([string]$Value).Trim() -eq 'true'
}

# A KQL dynamic bag (ByClassification and friends) as a name -> int map.
function _ReadBag {
    param([object]$Value)
    $bag = @{}
    if ($null -eq $Value) { return $bag }
    if ($Value -is [string]) {
        if ([string]::IsNullOrWhiteSpace($Value)) { return $bag }
        try { $Value = $Value | ConvertFrom-Json -Depth 8 } catch { return $bag }
        if ($null -eq $Value) { return $bag }
    }
    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($k in $Value.Keys) { $bag[[string]$k] = _ToInt $Value[$k] }
        return $bag
    }
    foreach ($p in $Value.PSObject.Properties) { $bag[$p.Name] = _ToInt $p.Value }
    return $bag
}

# Enabled Scheduled and NRT rules, the only kinds whose query, entity
# mappings and incident settings are authored by the workspace owner.
function _GetEnabledQueryRules {
    param([object]$Inventory)
    return @($Inventory.AlertRules | Where-Object {
        $null -ne $_ -and
        ((Get-PropOrDefault $_ 'kind' '') -in @('Scheduled', 'NRT')) -and
        (_ToBool (Get-PropOrDefault $_ 'properties.enabled' $false))
    })
}

function _GetRuleLabel {
    param([object]$Rule)
    return [string](Get-PropOrDefault $Rule 'properties.displayName' (Get-PropOrDefault $Rule 'name' '?'))
}

# GB ingested in the last 7 days, billable or not. IngestedLast7d was added
# to tables-with-data in the same change as these rules; older captures
# fall back to the billable figure.
function _GetIngested7d {
    param([object]$Row)
    if ($null -ne $Row -and $Row.PSObject.Properties.Name -contains 'IngestedLast7d') {
        return _ToDouble (Get-PropOrDefault $Row 'IngestedLast7d' 0)
    }
    return _ToDouble (Get-PropOrDefault $Row 'BillableLast7d' 0)
}

function _SampleSuffix {
    param([int]$Count, [int]$Shown = 5)
    if ($Count -gt $Shown) { return " (+ $($Count - $Shown) more)" }
    return ''
}

# ConvertFrom-Json turns ISO-8601 strings into DateTime; keep timestamps
# in evidence text as ISO-8601 UTC whichever shape arrives.
function _ToIsoTime {
    param([object]$Value)
    if ($null -eq $Value) { return '' }
    if ($Value -is [datetime]) { return $Value.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }
    return [string]$Value
}

# ------------------------------------------------------------
# SENT-036, Analytics rule closes mostly as false positive
# ------------------------------------------------------------
function Test-NoisyFalsePositiveRule {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    if (@($Inventory.RuleEffectiveness).Count -eq 0) { return $null }
    # Statistical floor of 20 closed incidents so a handful of closures
    # cannot condemn a rule.
    $noisy = @($Inventory.RuleEffectiveness | Where-Object {
        $null -ne $_ -and
        (_ToInt (Get-PropOrDefault $_ 'Closed' 0)) -ge 20 -and
        (_ToDouble (Get-PropOrDefault $_ 'FPRate' 0)) -gt 70
    } | Sort-Object { -(_ToDouble (Get-PropOrDefault $_ 'FPRate' 0)) })
    if ($noisy.Count -eq 0) { return $null }
    $sample = ($noisy | Select-Object -First 5 | ForEach-Object {
        "$(Get-PropOrDefault $_ 'RuleName' '?') ($(_ToInt (Get-PropOrDefault $_ 'FalsePositive' 0)) of $(_ToInt (Get-PropOrDefault $_ 'Closed' 0)) closed as false positive, $(_ToDouble (Get-PropOrDefault $_ 'FPRate' 0))%)"
    }) -join '; '
    return New-Finding -Evidence "$($noisy.Count) rule(s) closed mostly as false positive in the last 30 days: $sample$(_SampleSuffix $noisy.Count)." -Detail @{
        Count = $noisy.Count
        Rules = @($noisy | ForEach-Object {
            [pscustomobject]@{
                RuleName      = [string](Get-PropOrDefault $_ 'RuleName' '')
                AlertRuleId   = [string](Get-PropOrDefault $_ 'AlertRuleId' '')
                Closed        = _ToInt (Get-PropOrDefault $_ 'Closed' 0)
                FalsePositive = _ToInt (Get-PropOrDefault $_ 'FalsePositive' 0)
                FPRate        = _ToDouble (Get-PropOrDefault $_ 'FPRate' 0)
            }
        })
    }
}

# ------------------------------------------------------------
# SENT-037, Enabled rule has no entity mappings
# ------------------------------------------------------------
function Test-RuleEntityMappingsPresent {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    $rules = _GetEnabledQueryRules $Inventory
    if ($rules.Count -eq 0) { return $null }
    $unmapped = @($rules | Where-Object {
        @(Get-PropOrDefault $_ 'properties.entityMappings' @() | Where-Object { $null -ne $_ }).Count -eq 0
    })
    if ($unmapped.Count -eq 0) { return $null }
    $names = @($unmapped | ForEach-Object { _GetRuleLabel $_ })
    $sample = ($names | Select-Object -First 5) -join '; '
    return New-Finding -Evidence "$($unmapped.Count) of $($rules.Count) enabled Scheduled/NRT rule(s) have no entity mappings: $sample$(_SampleSuffix $unmapped.Count)." -Detail @{ Count = $unmapped.Count; Total = $rules.Count; Rules = $names }
}

# ------------------------------------------------------------
# SENT-038, Enabled rule does not create incidents
# ------------------------------------------------------------
function Test-RuleCreatesIncidents {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    $rules = _GetEnabledQueryRules $Inventory
    if ($rules.Count -eq 0) { return $null }
    # createIncident defaults to true when the block is absent, so only an
    # explicit false counts.
    $alertOnly = @($rules | Where-Object {
        $ic = Get-PropOrDefault $_ 'properties.incidentConfiguration' $null
        ($null -ne $ic) -and ($ic.PSObject.Properties.Name -contains 'createIncident') -and (-not (_ToBool $ic.createIncident))
    })
    if ($alertOnly.Count -eq 0) { return $null }
    $names = @($alertOnly | ForEach-Object { _GetRuleLabel $_ })
    $sample = ($names | Select-Object -First 5) -join '; '
    return New-Finding -Evidence "$($alertOnly.Count) enabled Scheduled/NRT rule(s) raise alerts without creating incidents: $sample$(_SampleSuffix $alertOnly.Count)." -Detail @{ Count = $alertOnly.Count; Rules = $names }
}

# ------------------------------------------------------------
# SENT-041, Legacy Microsoft incident-creation rules still enabled
# ------------------------------------------------------------
function Test-LegacyIncidentCreationRules {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    $legacy = @($Inventory.AlertRules | Where-Object {
        $null -ne $_ -and
        ((Get-PropOrDefault $_ 'kind' '') -eq 'MicrosoftSecurityIncidentCreation') -and
        (_ToBool (Get-PropOrDefault $_ 'properties.enabled' $false))
    })
    if ($legacy.Count -eq 0) { return $null }
    $xdrIncidents = @($Inventory.DataConnectors | Where-Object {
        $null -ne $_ -and
        ((Get-PropOrDefault $_ 'kind' '') -eq 'MicrosoftThreatProtection') -and
        ((Get-PropOrDefault $_ 'properties.dataTypes.incidents.state' '') -eq 'enabled')
    }).Count -gt 0
    $names = @($legacy | ForEach-Object { _GetRuleLabel $_ })
    $note = if ($xdrIncidents) {
        'The Defender XDR connector already syncs incidents, so these rules can create duplicate incidents for the same alerts.'
    } else {
        'The Defender XDR connector is not syncing incidents; enable that first so alert-to-incident creation moves to XDR before these rules are retired.'
    }
    return New-Finding -Evidence "$($legacy.Count) enabled Microsoft incident-creation rule(s): $(($names | Select-Object -First 5) -join '; ')$(_SampleSuffix $legacy.Count). $note" -Detail @{ Count = $legacy.Count; Rules = $names; XdrIncidentsConnected = $xdrIncidents }
}

# ------------------------------------------------------------
# SENT-050, Enabled rule queries the retired ThreatIntelligenceIndicator table
# ------------------------------------------------------------
function Test-RulesOnLegacyThreatIntelTable {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    if (@($Inventory.RuleTableReferences).Count -eq 0) { return $null }
    $hits = @($Inventory.RuleTableReferences | Where-Object {
        $null -ne $_ -and
        (_ToBool (Get-PropOrDefault $_ 'Enabled' $false)) -and
        (@(Get-PropOrDefault $_ 'Tables' @()) -contains 'ThreatIntelligenceIndicator')
    })
    if ($hits.Count -eq 0) { return $null }
    $names = @($hits | ForEach-Object { [string](Get-PropOrDefault $_ 'RuleName' (Get-PropOrDefault $_ 'RuleId' '?')) })
    return New-Finding -Evidence "$($hits.Count) enabled rule(s) query ThreatIntelligenceIndicator, which stopped receiving indicators on 31 July 2025: $(($names | Select-Object -First 5) -join '; ')$(_SampleSuffix $hits.Count). They match against an expiring indicator set and will go quiet without any error." -Detail @{ Count = $hits.Count; Rules = $names }
}

# ------------------------------------------------------------
# SENT-051, High-volume table with no enabled rule referencing it
# ------------------------------------------------------------
function Test-HighVolumeTableWithoutDetection {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    # Without the reference file there is no way to tell "no rule reads
    # this" from "the mapping was not computed", so stay quiet.
    if ($Inventory.RawFiles -notcontains 'rule-table-references.json') { return $null }
    if (-not $Inventory.TablesWithData) { return $null }
    $threshold = 5.0
    $referenced = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($ref in @($Inventory.RuleTableReferences)) {
        if ($null -eq $ref -or -not (_ToBool (Get-PropOrDefault $ref 'Enabled' $false))) { continue }
        foreach ($t in @(Get-PropOrDefault $ref 'Tables' @())) { if ($t) { [void]$referenced.Add([string]$t) } }
    }
    # Sentinel's own operational tables are outputs, not detection sources.
    $operational = @('SecurityIncident', 'SecurityAlert', 'Usage', 'Operation', 'LAQueryLogs', 'SentinelHealth', 'SentinelAudit', 'AzureMetrics')
    $uncovered = @($Inventory.TablesWithData | Where-Object {
        $t = [string](Get-PropOrDefault $_ 'DataType' '')
        $t -and ($operational -notcontains $t) -and (-not $referenced.Contains($t)) -and ((_GetBillable30d $_) -ge $threshold)
    } | Sort-Object { -(_GetBillable30d $_) })
    if ($uncovered.Count -eq 0) { return $null }

    # Suggest templates that read the table and are neither deployed already
    # nor deprecated, highest severity first.
    $severityRank = @{ High = 0; Medium = 1; Low = 2; Informational = 3 }
    $templates = @($Inventory.TemplateTableReferences | Where-Object {
        $null -ne $_ -and -not (_ToBool (Get-PropOrDefault $_ 'Deprecated' $false)) -and -not (_ToBool (Get-PropOrDefault $_ 'AlreadyDeployed' $false))
    })
    $rows = @(foreach ($table in $uncovered) {
        $name = [string](Get-PropOrDefault $table 'DataType' '')
        $candidates = @($templates | Where-Object { @(Get-PropOrDefault $_ 'Tables' @()) -contains $name } | Sort-Object {
            $sev = [string](Get-PropOrDefault $_ 'Severity' '')
            if ($severityRank.ContainsKey($sev)) { $severityRank[$sev] } else { 9 }
        }, { [string](Get-PropOrDefault $_ 'DisplayName' '') })
        [pscustomobject]@{
            Table              = $name
            Gb30d              = [math]::Round((_GetBillable30d $table), 1)
            SuggestedTemplates = @($candidates | Select-Object -First 3 | ForEach-Object { [string](Get-PropOrDefault $_ 'DisplayName' '') })
            MoreTemplates      = [math]::Max(0, $candidates.Count - 3)
        }
    })
    $totalGb = [math]::Round((($rows | ForEach-Object { $_.Gb30d }) | Measure-Object -Sum).Sum, 1)
    $sample = ($rows | Select-Object -First 5 | ForEach-Object {
        $hint = if ($_.SuggestedTemplates.Count -gt 0) { " (templates: $($_.SuggestedTemplates -join ', '))" } else { '' }
        "$($_.Table) $($_.Gb30d) GB$hint"
    }) -join '; '
    return New-Finding -Evidence "$($rows.Count) table(s) ingesting $totalGb GB in 30 days with no enabled analytics rule reading them: $sample$(_SampleSuffix $rows.Count)." -Detail @{ Count = $rows.Count; TotalGb30d = $totalGb; Tables = $rows }
}

# ------------------------------------------------------------
# SENT-052, Table that enabled rules depend on has gone silent
# ------------------------------------------------------------
function Test-SilentTableWithDependentRules {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    if (@($Inventory.RuleTableReferences).Count -eq 0) { return $null }
    if (-not $Inventory.TablesWithData) { return $null }
    # The extractor returns every bare identifier a query reads, which
    # includes functions and parsers. Intersecting with the workspace's
    # table list keeps only real tables; with no table list there is no
    # safe way to do that, so stay quiet.
    $known = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($t in @($Inventory.WorkspaceTables)) {
        $n = [string](Get-PropOrDefault $t 'name' '')
        if ($n) { [void]$known.Add($n) }
    }
    if ($known.Count -eq 0) { return $null }

    $ingested = @{}
    foreach ($row in $Inventory.TablesWithData) {
        $n = [string](Get-PropOrDefault $row 'DataType' '')
        if ($n) { $ingested[$n] = _GetIngested7d $row }
    }
    $rulesByTable = @{}
    foreach ($ref in @($Inventory.RuleTableReferences)) {
        if ($null -eq $ref -or -not (_ToBool (Get-PropOrDefault $ref 'Enabled' $false))) { continue }
        $ruleName = [string](Get-PropOrDefault $ref 'RuleName' (Get-PropOrDefault $ref 'RuleId' '?'))
        foreach ($t in @(Get-PropOrDefault $ref 'Tables' @())) {
            if (-not $t -or -not $known.Contains([string]$t)) { continue }
            if (-not $rulesByTable.ContainsKey($t)) { $rulesByTable[$t] = [System.Collections.Generic.List[string]]::new() }
            $rulesByTable[$t].Add($ruleName)
        }
    }
    $silent = @($rulesByTable.Keys | Where-Object { -not $ingested.ContainsKey($_) -or $ingested[$_] -le 0 } | Sort-Object)
    if ($silent.Count -eq 0) { return $null }
    $sample = ($silent | Select-Object -First 5 | ForEach-Object {
        "$_ ($($rulesByTable[$_].Count) rule(s): $((@($rulesByTable[$_]) | Select-Object -First 3) -join ', '))"
    }) -join '; '
    return New-Finding -Evidence "$($silent.Count) table(s) that enabled analytics rules read have ingested nothing in 7 days: $sample$(_SampleSuffix $silent.Count). Those rules cannot fire." -Detail @{
        Count  = $silent.Count
        Tables = @($silent | ForEach-Object { [pscustomobject]@{ Table = $_; Rules = @($rulesByTable[$_]) } })
    }
}

# ------------------------------------------------------------
# SENT-053, Playbook runs failed in the last 7 days
# ------------------------------------------------------------
function Test-PlaybookRunFailures {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    if (@($Inventory.PlaybookRuns).Count -eq 0) { return $null }
    $failing = @($Inventory.PlaybookRuns | Where-Object {
        $null -ne $_ -and (_ToInt (Get-PropOrDefault $_ 'Failed7d' 0)) -gt 0
    } | Sort-Object { -(_ToInt (Get-PropOrDefault $_ 'Failed7d' 0)) })
    if ($failing.Count -eq 0) { return $null }
    $sample = ($failing | Select-Object -First 5 | ForEach-Object {
        $last = _ToIsoTime (Get-PropOrDefault $_ 'LastFailureUtc' $null)
        $when = if ($last) { ", last $last" } else { '' }
        "$(Get-PropOrDefault $_ 'Playbook' '?') ($(_ToInt (Get-PropOrDefault $_ 'Failed7d' 0)) of $(_ToInt (Get-PropOrDefault $_ 'Runs7d' 0)) runs failed$when)"
    }) -join '; '
    return New-Finding -Evidence "$($failing.Count) playbook(s) had failed runs in the last 7 days: $sample$(_SampleSuffix $failing.Count)." -Detail @{
        Count     = $failing.Count
        Playbooks = @($failing | ForEach-Object {
            [pscustomobject]@{
                Playbook       = [string](Get-PropOrDefault $_ 'Playbook' '')
                Runs7d         = _ToInt (Get-PropOrDefault $_ 'Runs7d' 0)
                Failed7d       = _ToInt (Get-PropOrDefault $_ 'Failed7d' 0)
                LastFailureUtc = _ToIsoTime (Get-PropOrDefault $_ 'LastFailureUtc' $null)
            }
        })
    }
}

# ------------------------------------------------------------
# SENT-054, Installed solution deprecated or no longer in the catalogue
# ------------------------------------------------------------
function Test-DeprecatedContentHubSolutions {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    $installed = @($Inventory.ContentPackages | Where-Object { $null -ne $_ })
    $catalogue = @($Inventory.ContentProductPackages | Where-Object { $null -ne $_ })
    if ($installed.Count -eq 0 -or $catalogue.Count -eq 0) { return $null }
    $byId = @{}
    foreach ($p in $catalogue) {
        $id = [string](Get-PropOrDefault $p 'properties.contentId' '')
        if ($id) { $byId[$id] = $p }
    }
    $flagged = @(foreach ($p in $installed) {
        $id = [string](Get-PropOrDefault $p 'properties.contentId' '')
        if (-not $id) { continue }
        $name = [string](Get-PropOrDefault $p 'properties.displayName' $id)
        if (-not $byId.ContainsKey($id)) {
            [pscustomobject]@{ Solution = $name; ContentId = $id; Reason = 'not in catalogue' }
        } elseif (_ToBool (Get-PropOrDefault $byId[$id] 'properties.isDeprecated' $false)) {
            [pscustomobject]@{ Solution = $name; ContentId = $id; Reason = 'deprecated' }
        }
    })
    if ($flagged.Count -eq 0) { return $null }
    $sample = ($flagged | Select-Object -First 5 | ForEach-Object { "$($_.Solution) ($($_.Reason))" }) -join '; '
    return New-Finding -Evidence "$($flagged.Count) installed Content Hub solution(s) are deprecated or no longer in the catalogue: $sample$(_SampleSuffix $flagged.Count)." -Detail @{ Count = $flagged.Count; Solutions = $flagged }
}

# ------------------------------------------------------------
# SENT-055, Threat intelligence relies on a single feed
# ------------------------------------------------------------
function Test-ThreatIntelSingleFeed {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    # Connector inventory is the primary signal; without it the check
    # would report "no feed" on every failed capture.
    if ($Inventory.RawFiles -notcontains 'data-connectors-classic.json') { return $null }
    $tiKinds = @('MicrosoftThreatIntelligence', 'ThreatIntelligenceTaxii', 'ThreatIntelligence', 'ThreatIntelligenceUploadIndicatorsAPI', 'PremiumMicrosoftDefenderForThreatIntelligence')
    $feeds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($c in @($Inventory.DataConnectors)) {
        $kind = [string](Get-PropOrDefault $c 'kind' '')
        if ($kind -and $tiKinds -contains $kind) { [void]$feeds.Add($kind) }
    }
    # Indicators from a non-Microsoft source count as a feed even when the
    # connector that brought them in is not in the classic list (TAXII and
    # upload-API sources show up here by name).
    foreach ($row in @($Inventory.ThreatIntelCounts)) {
        $src = [string](Get-PropOrDefault $row 'SourceSystem' '')
        if ($src -and $src -notmatch '^(Microsoft|Azure Sentinel)') { [void]$feeds.Add("source: $src") }
    }
    if ($feeds.Count -gt 1) { return $null }
    $evidence = if ($feeds.Count -eq 0) {
        'No threat intelligence feed is connected and no indicators were seen in 30 days.'
    } else {
        "Threat intelligence comes from a single feed ($(@($feeds) -join ''))."
    }
    return New-Finding -Evidence "$evidence Every TI-based detection depends on that one source." -Detail @{ Feeds = @($feeds) }
}

# ------------------------------------------------------------
# SENT-056, Azure Firewall logs collected twice
# ------------------------------------------------------------
function Test-AzureFirewallDuplicateLogging {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    if (@($Inventory.AzureDiagnosticsCategories).Count -eq 0) { return $null }
    if (-not $Inventory.TablesWithData) { return $null }
    $legacy = @($Inventory.AzureDiagnosticsCategories | Where-Object {
        $null -ne $_ -and ([string](Get-PropOrDefault $_ 'Category' '')) -match '^(AzureFirewall|AZFW)'
    })
    $structured = @($Inventory.TablesWithData | Where-Object {
        ([string](Get-PropOrDefault $_ 'DataType' '')) -match '^AZFW' -and (_GetIngested7d $_) -gt 0
    })
    if ($legacy.Count -eq 0 -or $structured.Count -eq 0) { return $null }
    $legacyRows = ($legacy | ForEach-Object { _ToInt (Get-PropOrDefault $_ 'LogCount' 0) } | Measure-Object -Sum).Sum
    $categories = @($legacy | ForEach-Object { [string](Get-PropOrDefault $_ 'Category' '') } | Sort-Object -Unique)
    $tables = @($structured | ForEach-Object { [string](Get-PropOrDefault $_ 'DataType' '') } | Sort-Object -Unique)
    $structuredGb = [math]::Round((($structured | ForEach-Object { _GetBillable30d $_ }) | Measure-Object -Sum).Sum, 1)
    return New-Finding -Evidence "Azure Firewall writes to both AzureDiagnostics ($($categories -join ', '); $($legacyRows.ToString('N0')) rows in 7 days) and the resource-specific tables ($($tables -join ', '); $structuredGb GB in 30 days). The same events are ingested and billed twice." -Detail @{ LegacyCategories = $categories; LegacyRows7d = $legacyRows; StructuredTables = $tables; StructuredGb30d = $structuredGb }
}

# ------------------------------------------------------------
# SENT-057, Incidents closed without a classification
# ------------------------------------------------------------
function Test-IncidentsClosedUnclassified {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    if (@($Inventory.IncidentsSummary).Count -eq 0) { return $null }
    $row = $Inventory.IncidentsSummary[0]
    # ByClassification arrived with this rule; an older capture has nothing
    # to evaluate.
    $bagValue = Get-PropOrDefault $row 'ByClassification' $null
    if ($null -eq $bagValue) { return $null }
    $closed = _ToInt (Get-PropOrDefault $row 'Closed' 0)
    if ($closed -lt 10) { return $null }            # statistical floor, small samples lie
    $bag = _ReadBag $bagValue
    $unclassified = [int]$bag['Undetermined'] + [int]$bag['Unclassified']
    $ratio = $unclassified / [double]$closed
    if ($ratio -le 0.5) { return $null }
    return New-Finding -Evidence "$unclassified of $closed closed incidents ($([math]::Round($ratio * 100, 0))%) were closed as Undetermined or with no classification. Without a true or false positive verdict, false-positive rates and rule tuning have nothing to work from." -Detail @{ Closed = $closed; Undetermined = [int]$bag['Undetermined']; Unclassified = [int]$bag['Unclassified']; ByClassification = $bag }
}

# ------------------------------------------------------------
# SENT-058, No hunting activity recorded
# ------------------------------------------------------------
function Test-HuntingActivityRecorded {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    # Both captures must have run: hunts.json is only written on success,
    # and an empty bookmarks list means nothing without it.
    if ($Inventory.RawFiles -notcontains 'hunts.json' -or $Inventory.RawFiles -notcontains 'bookmarks.json') { return $null }
    if (@($Inventory.Hunts).Count -gt 0 -or @($Inventory.Bookmarks).Count -gt 0) { return $null }
    return New-Finding -Evidence 'No hunts and no bookmarks exist in the workspace, so there is no record of proactive hunting in Sentinel.' -Detail @{ Hunts = 0; Bookmarks = 0 }
}

#Requires -Version 7.6

<#
.SYNOPSIS
    Build the figures for and write 25-mitre-coverage.md (part 1 of 3).

.DESCRIPTION
    A step of the Blueprint renderer. Steps run in order and pass their results
    to later ones through the render context, so this one may also prepare
    figures that a later page uses.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/MitreCoverage/Write-BlueprintMitreCoverageSection.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-16
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.
function Write-BlueprintMitreCoverageSection {
    <#
    .SYNOPSIS
        Build the figures for and write 25-mitre-coverage.md (part 1 of 3).

    .PARAMETER Context
        The render context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the render context.
    $connectors = $Context.connectors
    $k = $Context.k
    $rules = $Context.rules

    # ---------------------------------------------------------------------------
    # Section: 20-analytics-rules
    # ---------------------------------------------------------------------------
    $ruleRows = $rules | ForEach-Object {
        [pscustomobject]@{
            Kind     = $_.kind
            Name     = $_.properties.displayName
            Severity = $_.properties.severity
            Enabled  = if ($_.properties.enabled) { 'Yes' } else { 'No' }
            Tactics  = (Format-TacticList $_.properties.tactics)
        }
    }

    # Per-kind / per-state aggregate counts. Microsoft-managed kinds (Fusion etc)
    # are excluded from the Scheduled/NRT counts because they aren't user-editable.
    $schedEnabled  = @($rules | Where-Object { $_.kind -eq 'Scheduled' -and $_.properties.enabled }).Count
    $schedDisabled = @($rules | Where-Object { $_.kind -eq 'Scheduled' -and -not $_.properties.enabled }).Count
    $nrtEnabled    = @($rules | Where-Object { $_.kind -eq 'NRT' -and $_.properties.enabled }).Count
    $nrtDisabled   = @($rules | Where-Object { $_.kind -eq 'NRT' -and -not $_.properties.enabled }).Count

    # Mouldy rules — Scheduled / NRT rules enabled but last-modified > 1 year ago.
    $yearAgo = (Get-Date).ToUniversalTime().AddYears(-1)
    $mouldyRows = $rules | Where-Object {
        $_.kind -in @('Scheduled','NRT') -and
        $_.properties.enabled -and
        $_.properties.lastModifiedUtc -and
        ([datetime]$_.properties.lastModifiedUtc) -lt $yearAgo
    } | ForEach-Object {
        [pscustomobject]@{
            Name         = $_.properties.displayName
            Kind         = $_.kind
            Severity     = $_.properties.severity
            LastModified = Format-DateUtc $_.properties.lastModifiedUtc
        }
    }

    # MS Incident Creation rules — these aren't user-editable detection rules
    # in the usual sense; they translate first-party security alerts into
    # Sentinel incidents based on per-product filter criteria. Surface those
    # filter fields explicitly since they don't fit the standard row schema.
    $msIncidentRows = $rules | Where-Object { $_.kind -eq 'MicrosoftSecurityIncidentCreation' } | ForEach-Object {
        [pscustomobject]@{
            Name              = $_.properties.displayName
            Product           = $_.properties.productFilter
            Severities        = (@($_.properties.severitiesFilter) -join ', ')
            Includes          = (@($_.properties.displayNamesFilter) -join '; ')
            Excludes          = (@($_.properties.displayNamesExcludeFilter) -join '; ')
            Enabled           = if ($_.properties.enabled) { 'Yes' } else { 'No' }
        }
    }

    # Template mismatch — rules whose templateVersion does not match the latest
    # template version. Look up the template by alertRuleTemplateName in the
    # captured alert-rule-templates.json.
    $alertRuleTemplates = Read-BlueprintRawArray 'alert-rule-templates.json'
    $templateByName = @{}
    foreach ($t in $alertRuleTemplates) {
        if ($t.name) { $templateByName[$t.name] = $t }
    }
    $mismatchRows = $rules | Where-Object {
        $_.properties.alertRuleTemplateName -and
        $_.properties.templateVersion -and
        $templateByName.ContainsKey($_.properties.alertRuleTemplateName) -and
        $templateByName[$_.properties.alertRuleTemplateName].properties.version -and
        $templateByName[$_.properties.alertRuleTemplateName].properties.version -ne $_.properties.templateVersion
    } | ForEach-Object {
        $tplName = $_.properties.alertRuleTemplateName
        [pscustomobject]@{
            Name           = $_.properties.displayName
            Kind           = $_.kind
            CurrentVersion = $_.properties.templateVersion
            LatestVersion  = $templateByName[$tplName].properties.version
        }
    }

    # Rule-kind distribution for the headline.
    $ruleKindCounts = @{}
    foreach ($r in $rules) {
        $k = if ($r.kind) { [string]$r.kind } else { 'unknown' }
        if (-not $ruleKindCounts.ContainsKey($k)) { $ruleKindCounts[$k] = 0 }
        $ruleKindCounts[$k]++
    }
    $schedNote = if ($ruleKindCounts.ContainsKey('Scheduled')) { "$($ruleKindCounts['Scheduled']) deployed" } else { 'not deployed' }
    $msicNote  = if ($ruleKindCounts.ContainsKey('MicrosoftSecurityIncidentCreation')) {
        "$($ruleKindCounts['MicrosoftSecurityIncidentCreation']) deployed"
    } else { 'not deployed' }

    # Fusion vs Defender XDR Correlation Engine state. When a workspace is
    # onboarded to the Microsoft Defender unified portal (USOP), Microsoft
    # automatically disables the Fusion analytic rule and the Defender XDR
    # Correlation Engine takes over alert-to-incident correlation. The
    # canonical, capture-derivable signal is the combination of:
    #   - whether a Fusion rule exists and is enabled, AND
    #   - whether the Microsoft Defender XDR connector
    #     (kind = MicrosoftThreatProtection) is enabled.
    # The four (fusion × defender) cells map to four reader-facing narratives
    # below.
    $fusionRules    = @($rules | Where-Object { $_.kind -eq 'Fusion' })
    $fusionPresent  = $fusionRules.Count -gt 0
    $fusionEnabled  = @($fusionRules | Where-Object { $_.properties.enabled }).Count -gt 0

    $m365DefenderConnected = $false
    foreach ($c in $connectors) {
        if ($c.kind -ne 'MicrosoftThreatProtection') { continue }
        $dts = $c.properties.dataTypes
        if ($dts) {
            foreach ($p in $dts.PSObject.Properties) {
                if ($p.Value.state -eq 'Enabled') { $m365DefenderConnected = $true; break }
            }
        }
        if ($m365DefenderConnected) { break }
    }

    $correlationState = if ($fusionEnabled -and $m365DefenderConnected) {
        '**Fusion enabled, Defender XDR connector enabled.** If this workspace is onboarded to the Microsoft Defender unified portal (USOP), Microsoft auto-disables Fusion regardless of the displayed state above and the Defender XDR Correlation Engine performs alert-to-incident correlation. Confirm by checking the workspace''s onboarding state in the Defender portal. If it is onboarded, treat the displayed Fusion state as informational only.'
    } elseif ((-not $fusionEnabled) -and $m365DefenderConnected) {
        '**Fusion disabled, Defender XDR connector enabled.** This workspace is using the **Defender XDR Correlation Engine** for alert-to-incident correlation. Microsoft auto-disables the Fusion rule on workspaces onboarded to the Defender unified portal, where Defender XDR''s correlation replaces it.'
    } elseif ($fusionEnabled -and (-not $m365DefenderConnected)) {
        '**Fusion enabled, no Defender XDR connector.** Fusion is performing multi-source ML-based incident correlation across Sentinel data sources. Onboarding the workspace to the Defender unified portal would auto-disable Fusion and hand correlation to Defender XDR.'
    } elseif ($fusionPresent -and -not $fusionEnabled -and -not $m365DefenderConnected) {
        '**Fusion present but disabled, no Defender XDR connector.** No ML-based incident correlation is active on this workspace.'
    } else {
        '**No Fusion rule deployed, no Defender XDR connector.** No ML-based incident correlation. Either enable the Fusion rule for multi-source correlation, or onboard to the Defender unified portal to inherit the Defender XDR Correlation Engine.'
    }

    # The rule kinds as data for the SharePoint graphic: every kind with its
    # settings, what it does, and how many this workspace deploys and enables.
    $ruleKindEnabled = @{}
    foreach ($r in $rules) {
        if (-not ($r.properties -and $r.properties.enabled -eq $true)) { continue }
        $k = if ($r.kind) { [string]$r.kind } else { 'unknown' }
        if (-not $ruleKindEnabled.ContainsKey($k)) { $ruleKindEnabled[$k] = 0 }
        $ruleKindEnabled[$k]++
    }
    $ruleKindDefs = @(
        [ordered]@{
            kind = 'Scheduled'
            label = 'Scheduled'
            summary = 'A KQL query on a schedule; raises an alert when its results pass a threshold.'
            fields = @('queryFrequency', 'queryPeriod', 'triggerThreshold', 'query')
            legacy = $false
        }
        [ordered]@{
            kind = 'NRT'
            label = 'Near real time'
            summary = 'A KQL query run every minute with no threshold, for detections that cannot wait.'
            fields = @('query', 'eventGrouping')
            legacy = $false
        }
        [ordered]@{
            kind = 'Fusion'
            label = 'Fusion'
            summary = 'Microsoft machine learning that correlates low-fidelity alerts into high-fidelity incidents.'
            fields = @('alertRuleTemplateName', 'sourceSettings')
            legacy = $false
        }
        [ordered]@{
            kind = 'MicrosoftSecurityIncidentCreation'
            label = 'Microsoft incident creation'
            summary = 'Turns alerts from a Microsoft security product into incidents: the pattern from before Defender XDR.'
            fields = @('productFilter', 'severitiesFilter', 'displayNamesFilter', 'displayNamesExcludeFilter')
            legacy = $true
        }
        [ordered]@{
            kind = 'ThreatIntelligence'
            label = 'Threat intelligence'
            summary = 'Matches Microsoft threat intelligence indicators against the workspace logs.'
            fields = @('templateVersion')
            legacy = $false
        }
        [ordered]@{
            kind = 'MLBehaviorAnalytics'
            label = 'ML behaviour analytics'
            summary = 'Built-in machine learning anomaly detections, such as unusual SSH or RDP sign-ins.'
            fields = @('alertRuleTemplateName')
            legacy = $false
        }
    )
    $ruleKindItems = [System.Collections.Generic.List[object]]::new()
    foreach ($d in $ruleKindDefs) {
        $n = if ($ruleKindCounts.ContainsKey($d.kind)) { $ruleKindCounts[$d.kind] } else { 0 }
        # The five kinds every workspace can have always show; ML behaviour analytics only when deployed.
        if ($d.kind -eq 'MLBehaviorAnalytics' -and $n -eq 0) { continue }
        $item = [ordered]@{}; foreach ($key in $d.Keys) { $item[$key] = $d[$key] }
        $item.deployed = $n
        $item.enabled = $(if ($ruleKindEnabled.ContainsKey($d.kind)) { $ruleKindEnabled[$d.kind] } else { 0 })
        $ruleKindItems.Add($item)
    }
    foreach ($k in @($ruleKindCounts.Keys | Where-Object { $_ -notin @($ruleKindDefs | ForEach-Object { $_.kind }) } | Sort-Object)) {
        $ruleKindItems.Add([ordered]@{
            kind = $k
            label = $k
            summary = 'A rule kind this report does not describe.'
            fields = @()
            legacy = $false
            deployed = $ruleKindCounts[$k]
            enabled = $(if ($ruleKindEnabled.ContainsKey($k)) { $ruleKindEnabled[$k] } else { 0 })
        })
    }
    $ruleKindsVisualLine = Format-VisualLine -Kind 'rule-kinds' -Data ([ordered]@{
        total  = $rules.Count
        common = @('id', 'kind', 'displayName', 'severity', 'enabled', 'lastModifiedUtc', 'tactics', 'techniques')
        kinds  = $ruleKindItems.ToArray()
    })

    # Left in the render context for later sections.
    $Context.c = $c
    $Context.correlationState = $correlationState
    $Context.d = $d
    if (Get-Variable -Name 'k' -Scope 0 -ErrorAction Ignore) { $Context.k = $k }
    $Context.key = $key
    $Context.m365DefenderConnected = $m365DefenderConnected
    $Context.mismatchRows = $mismatchRows
    $Context.mouldyRows = $mouldyRows
    $Context.msicNote = $msicNote
    $Context.msIncidentRows = $msIncidentRows
    if (Get-Variable -Name 'n' -Scope 0 -ErrorAction Ignore) { $Context.n = $n }
    $Context.nrtDisabled = $nrtDisabled
    $Context.nrtEnabled = $nrtEnabled
    $Context.p = $p
    $Context.r = $r
    $Context.ruleKindsVisualLine = $ruleKindsVisualLine
    $Context.ruleRows = $ruleRows
    $Context.schedDisabled = $schedDisabled
    $Context.schedEnabled = $schedEnabled
    $Context.schedNote = $schedNote
    $Context.t = $t
}

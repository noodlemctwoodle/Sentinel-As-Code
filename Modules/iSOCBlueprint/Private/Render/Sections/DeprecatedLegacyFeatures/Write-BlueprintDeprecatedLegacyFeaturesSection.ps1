#Requires -Version 7.6

<#
.SYNOPSIS
    Build the figures for and write 02-deprecated-legacy-features.md.

.DESCRIPTION
    A step of the Blueprint renderer. Steps run in order and pass their results
    to later ones through the render context, so this one may also prepare
    figures that a later page uses.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/DeprecatedLegacyFeatures/Write-BlueprintDeprecatedLegacyFeaturesSection.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.
function Write-BlueprintDeprecatedLegacyFeaturesSection {
    <#
    .SYNOPSIS
        Build the figures for and write 02-deprecated-legacy-features.md.

    .PARAMETER Context
        The render context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the render context.
    $classicTables01 = $Context.classicTables01
    $clv1Days = $Context.clv1Days
    $connectors = $Context.connectors
    $f = $Context.f
    $has01 = $Context.has01
    $legacyRows = $Context.legacyRows
    $m = $Context.m
    $mmaMachines01 = $Context.mmaMachines01
    $n = $Context.n
    $rawRoot = $Context.rawRoot
    $tiLegacyRows01 = $Context.tiLegacyRows01
    $tiLegacyRules01 = $Context.tiLegacyRules01
    $tipDays = $Context.tipDays
    $today = $Context.today
    $xdrDays = $Context.xdrDays

    # Section 02: retired and retiring platform features, with the deadlines
    # still ahead and whether this workspace uses each one.
    # The runway as data for the SharePoint graphic: each deadline, and whether
    # this workspace still uses what it retires (null when it cannot say).
    $runwayUse = { param([bool]$Captured, [bool]$InUse) if ($Captured) { $InUse } else { $null } }
    $mmaCaptured = & $has01 'ama-mma-migration.json'
    $tiCaptured = (& $has01 'threat-intel-tables.json') -or (& $has01 'alert-rules.json')
    $tipConnectors = @($connectors | Where-Object { $_ -and [string]$_.kind -eq 'ThreatIntelligence' }).Count
    $runwayVisualLine = Format-VisualLine -Kind 'runway' -Data ([ordered]@{ today = $today; items = @(
        [ordered]@{ label = 'MMA / OMS agent retired'; date = '2024-08-31'; state = 'done'; inUse = (& $runwayUse $mmaCaptured ($mmaMachines01 -gt 0)); evidence = (Format-BlueprintPlural $mmaMachines01 'machine') }
        [ordered]@{ label = 'MMA ingestion degraded'; date = '2025-02-01'; state = 'done'; inUse = (& $runwayUse $mmaCaptured ($mmaMachines01 -gt 0)); evidence = (Format-BlueprintPlural $mmaMachines01 'machine') }
        [ordered]@{ label = 'Legacy threat intelligence ingestion stopped'; date = '2025-07-31'; state = 'done'; inUse = (& $runwayUse $tiCaptured ($tiLegacyRows01 -gt 0 -or $tiLegacyRules01 -gt 0)); evidence = "$(Format-BlueprintPlural $tiLegacyRows01 'record'), $(Format-BlueprintPlural $tiLegacyRules01 'rule')" }
        [ordered]@{ label = 'HTTP Data Collector API retires'; date = '2026-09-14'; state = 'crit'; inUse = (& $runwayUse (& $has01 'workspace-tables.json') ($classicTables01.Count -gt 0)); evidence = (Format-BlueprintPlural $classicTables01.Count 'classic table') }
        [ordered]@{ label = 'Sentinel in the Azure portal retires (move to the Defender portal)'; date = '2027-03-31'; state = 'crit'; inUse = $null; evidence = '' }
        [ordered]@{ label = 'Legacy threat intelligence platform connector deprecates'; date = '2027-06-30'; state = 'active'; inUse = (& $runwayUse (& $has01 'data-connectors-classic.json') ($tipConnectors -gt 0)); evidence = 'connector connected' }
    ) })

    $legacyBody = @"
$(Format-Banner -Title "Deprecated and Legacy Features")

What Microsoft has retired or is retiring on the Sentinel platform, and whether this workspace still depends on any of it. Each row links to the page with the detail.

## Platform deprecation runway

``````mermaid
gantt
$runwayVisualLine
    title Microsoft Sentinel platform deprecation runway
    dateFormat YYYY-MM-DD
    axisFormat %b %Y

    section Past deadlines
    MMA / OMS agent retired                :done,  mma,  2024-08-31, 1d
    MMA ingestion degraded                 :done,  mmaI, 2025-02-01, 1d
    Legacy TI ingestion stopped            :done,  ti,   2025-07-31, 1d

    section Upcoming
    Today                                  :milestone, today, $today, 0d
    HTTP Data Collector API retires        :crit,  clv1, $today, ${clv1Days}d
    Legacy TIP connector deprecates        :active, tip,  $today, ${tipDays}d
    Sentinel Azure portal retires (→ XDR)  :crit,  xdr,  $today, ${xdrDays}d
``````

## Legacy features still in use

Each retired or retiring feature the Blueprint can see, whether this workspace still uses it, and where the detail is. Sentinel's move from the Azure portal to the Defender portal is on the runway above; Defender-portal onboarding cannot be read from the workspace.

$(Format-BlueprintTable -Items $legacyRows -Columns 'Feature','Status','Evidence','Where')

[What's new and deprecated in Microsoft Sentinel (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/whats-new)
"@
    Write-BlueprintSection '02-deprecated-legacy-features.md' $legacyBody
}

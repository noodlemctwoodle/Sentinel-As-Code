#Requires -Version 7.6

<#
.SYNOPSIS
    Build the figures for and write 38-summary-rules.md.

.DESCRIPTION
    A step of the Blueprint renderer. Steps run in order and pass their results
    to later ones through the render context, so this one may also prepare
    figures that a later page uses.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/SummaryRules/Write-BlueprintSummaryRulesSection.ps1
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
function Write-BlueprintSummaryRulesSection {
    <#
    .SYNOPSIS
        Build the figures for and write 38-summary-rules.md.

    .PARAMETER Context
        The render context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the render context.
    $props = $Context.props

    # Section 38 — Summary rules (TOC 4.3.5)
    # Schema note: the capture comes from `.../workspaces/<ws>/summaryLogs` (under
    # the OperationalInsights provider, not Sentinel). Each item exposes
    # `properties.ruleType`, `properties.ruleDefinition.query`,
    # `properties.ruleDefinition.binSize`, `properties.ruleDefinition.timeSelector`,
    # `properties.ruleDefinition.destinationTable`, `properties.isActive`,
    # `properties.statusCode`. The previous renderer included a `BinDelay` column
    # that doesn't exist in the API response (always-empty). `isActive` and
    # `statusCode` ARE present and signal whether the rule is actually running —
    # the first rule on stl-sec-siem-law has isActive=false + status=DataPlaneError,
    # evidence of a broken rule that the old shape never surfaced. Field names
    # round-trip through ConvertFrom-Json as camelCase; PowerShell's PSObject
    # property access is case-insensitive so the old PascalCase access "worked"
    # accidentally for the fields that happened to exist.
    $summaryRules = Read-BlueprintRawArray 'summary-rules.json'
    $summaryRows = $summaryRules | ForEach-Object {
        $props = $_.properties
        $isActive = if ($props.PSObject.Properties.Name -contains 'isActive') { $props.isActive } else { $null }
        $status = if ($props.PSObject.Properties.Name -contains 'statusCode') { [string]$props.statusCode } else { '' }
        [pscustomobject]@{
            Name             = $_.name
            RuleType         = $props.ruleType
            DestinationTable = $props.ruleDefinition.destinationTable
            BinSize          = $props.ruleDefinition.binSize
            TimeSelector     = $props.ruleDefinition.timeSelector
            Active           = if ($null -eq $isActive) { '?' } elseif ($isActive) { 'Yes' } else { 'No' }
            Status           = if ($status) { $status } else { 'Ok' }
        }
    }
    $brokenSummary = @($summaryRows | Where-Object { $_.Active -eq 'No' -or $_.Status -ne 'Ok' })
    $summaryWarning = if ($brokenSummary.Count -gt 0) {
        "`n<!-- bp:tone critical -->`n`n> **$(Format-BlueprintPlural $brokenSummary.Count 'summary rule') $(if ($brokenSummary.Count -eq 1) { 'is' } else { 'are' }) inactive or in error.** Inspect the `Status` column: `DataPlaneError` typically means the underlying source table is missing or the query failed at last execution.`n"
    } else { '' }
    # Active vs Errored pie (only when there's something to chart).
    $summaryActiveCount = @($summaryRows | Where-Object { $_.Active -eq 'Yes' -and $_.Status -eq 'Ok' }).Count
    $summaryBrokenCount = @($summaryRows | Where-Object { $_.Active -ne 'Yes' -or $_.Status -ne 'Ok' }).Count
    $summaryChartBlock = if ($summaryRows.Count -gt 0) {
        @"

## Health

``````mermaid
pie showData title Summary rule health
    "Active & Ok" : $summaryActiveCount
    "Inactive or errored" : $summaryBrokenCount
``````
"@
    } else { '' }

    Write-BlueprintSection '38-summary-rules.md' (@"
$(Format-Banner -Title 'Summary Rules  (TOC 4.3.5)')

Summary rules pre-aggregate high-volume tables on a schedule into a derived table. They cut query cost on noisy data.
$summaryWarning$summaryChartBlock

$(Format-BlueprintTable -Items $summaryRows -Columns 'Name','RuleType','DestinationTable','BinSize','TimeSelector','Active','Status')

[Summary rules (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/summary-rules)
"@)

    # Left in the render context for later sections.
    $Context.summaryRules = $summaryRules
}

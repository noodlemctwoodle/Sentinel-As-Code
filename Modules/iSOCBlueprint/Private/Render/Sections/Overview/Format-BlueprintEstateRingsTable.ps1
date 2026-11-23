#Requires -Version 7.6

<#
.SYNOPSIS
    Render the estate pipeline stages as in-use, of and share.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/Overview/Format-BlueprintEstateRingsTable.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Format-BlueprintEstateRingsTable {
    <#
    .SYNOPSIS
        Render the estate pipeline stages as in-use, of and share.

    .DESCRIPTION
        The four pipeline stages as in-use / of / share, with a rating so the reader
        does not have to do the division: 80% and above is Strong, 65% and above is
        Fair, and anything lower is Weak. A stage with nothing to measure against
        shows n/a for share and rating.

    .PARAMETER Estate
        The estate model from New-BlueprintEstateModel.

    .OUTPUTS
        [string] of Markdown.
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param($Estate)
    $row = {
        param([string]$Stage, [int]$Value, [int]$Of)
        if ($Of -le 0) { return "| $Stage | $(Format-BlueprintCount $Value) | $(Format-BlueprintCount $Of) | _n/a_ | _n/a_ |" }
        $pct = [int][math]::Round(100.0 * $Value / $Of, 0)
        $badge = if ($pct -ge 80) { 'Strong' } elseif ($pct -ge 65) { 'Fair' } else { 'Weak' }
        return "| $Stage | $(Format-BlueprintCount $Value) | $(Format-BlueprintCount $Of) | $pct% | $badge |"
    }
    @"
| Stage | In use | Of | Share | Rating |
|---|---:|---:|---:|---|
$(& $row -Stage 'Ingestion: tables still receiving data ({recent-d}, of those with data in {lookback-d})' -Value $Estate.TablesActive -Of $Estate.TablesSeen)
$(& $row -Stage 'Detection: active tables read by at least one enabled rule' -Value $Estate.TablesCovered -Of $Estate.TablesActive)
$(& $row -Stage 'Alerts: enabled Scheduled/NRT rules that fired in {lookback-d}' -Value $Estate.RulesFired -Of $Estate.RulesQueryEnabled)
$(& $row -Stage 'Incidents: closed, of those created in {lookback-d}' -Value $Estate.IncidentsClosed -Of $Estate.Incidents)
"@
}

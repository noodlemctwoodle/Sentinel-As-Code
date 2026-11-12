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
    Version:      0.1.0
    Last Updated: 2026-11-12
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Format-BlueprintEstateRingsTable {
    # The four pipeline stages as in-use / of / share, with a rating so the
    # reader does not have to do the division: 80%+ strong, 65%+ fair.
    param($Estate)
    function _Row([string]$Stage, [int]$Value, [int]$Of) {
        if ($Of -le 0) { return "| $Stage | $(Format-BlueprintCount $Value) | $(Format-BlueprintCount $Of) | _n/a_ | _n/a_ |" }
        $pct = [int][math]::Round(100.0 * $Value / $Of, 0)
        $badge = if ($pct -ge 80) { 'Strong' } elseif ($pct -ge 65) { 'Fair' } else { 'Weak' }
        return "| $Stage | $(Format-BlueprintCount $Value) | $(Format-BlueprintCount $Of) | $pct% | $badge |"
    }
    @"
| Stage | In use | Of | Share | Rating |
|---|---:|---:|---:|---|
$(_Row 'Ingestion: tables still receiving data ({recent-d}, of those with data in {lookback-d})' $Estate.TablesActive $Estate.TablesSeen)
$(_Row 'Detection: active tables read by at least one enabled rule' $Estate.TablesCovered $Estate.TablesActive)
$(_Row 'Alerts: enabled Scheduled/NRT rules that fired in {lookback-d}' $Estate.RulesFired $Estate.RulesQueryEnabled)
$(_Row 'Incidents: closed, of those created in {lookback-d}' $Estate.IncidentsClosed $Estate.Incidents)
"@
}

#Requires -Version 7.6

<#
.SYNOPSIS
    Build the figures for and write 21-rule-performance.md.

.DESCRIPTION
    A step of the Blueprint renderer. Steps run in order and pass their results
    to later ones through the render context, so this one may also prepare
    figures that a later page uses.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/RulePerformance/Write-BlueprintRulePerformanceSection.ps1
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
function Write-BlueprintRulePerformanceSection {
    <#
    .SYNOPSIS
        Build the figures for and write 21-rule-performance.md.

    .PARAMETER Context
        The render context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the render context.
    $analyticsLinks = $Context.analyticsLinks
    $m = $Context.m
    $n = $Context.n
    $volumeSection = $Context.volumeSection

    # Section 21: how the rules perform, alert volume and closure verdicts.
    Write-BlueprintSection '21-rule-performance.md' (@(
            "$(Format-Banner -Title "Rule Performance")`n`nHow much each detection fires and how its incidents are closed. The rule inventory is in [20-analytics-rules.md](20-analytics-rules.md); alerts by severity, product and provider are in [16-alerts.md](16-alerts.md).",
            $volumeSection,
            $analyticsLinks) -join [Environment]::NewLine)
}

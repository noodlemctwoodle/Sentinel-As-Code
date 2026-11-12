#Requires -Version 7.6

<#
.SYNOPSIS
    Count enabled rules by MITRE tactic.

.DESCRIPTION
    A step of the SharePoint site build. Steps run in order and pass their results
    to later ones through the build context.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Site/Steps/Build-SiteMitre.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, SharePoint site build
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Build-SiteMitre {
    <#
    .SYNOPSIS
        Count enabled rules by MITRE tactic.

    .PARAMETER Context
        The build context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the build context.
    $alertRaw = $Context.alertRaw

    # ---- MITRE coverage ----
    $tacticCounts = @{}
    foreach ($r in $alertRaw) {
        if (-not ($r.properties -and $r.properties.enabled)) { continue }
        foreach ($t in @($r.properties.tactics)) {
            if (-not $t) { continue }
            if (-not $tacticCounts.ContainsKey($t)) { $tacticCounts[$t] = 0 }
            $tacticCounts[$t]++
        }
    }
    $mitre = @()
    foreach ($k in $script:MitreTactics.Keys) {
        $n = if ($tacticCounts.ContainsKey($k)) { $tacticCounts[$k] } else { 0 }
        $status = if ($n -eq 0) { 'None' } elseif ($n -lt $script:MitreCoveredThreshold) { 'Thin' } else { 'Covered' }
        $mitre += [ordered]@{ id = $script:MitreTactics[$k][0]; tactic = $script:MitreTactics[$k][1]; rules = $n; status = $status }
    }
    $mitreCovered = @($mitre | Where-Object { $_.status -eq 'Covered' }).Count

    # Left in the build context for later steps.
    $Context.k = $k
    $Context.mitre = $mitre
    $Context.mitreCovered = $mitreCovered
    if (Get-Variable -Name 'n' -Scope 0 -ErrorAction Ignore) { $Context.n = $n }
    $Context.r = $r
}

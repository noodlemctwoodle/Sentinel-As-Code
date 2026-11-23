#Requires -Version 7.6

<#
.SYNOPSIS
    A rule's ATT&CK ids: parent techniques and sub-techniques, upper-case and de-duplicated, with...

.DESCRIPTION
    One of the helpers beside Get-AttackCoverage.ps1, which describes the whole.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Lookup/Get-RuleAttackId.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-13
    Version:      0.1.0
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-RuleAttackId {
    <#
    .SYNOPSIS
        A rule's ATT&CK ids: parent techniques and sub-techniques,
        upper-case and de-duplicated, with every sub-technique's parent
        added.

    .PARAMETER Rule
        One alertRules object as the collector saves it.

    .OUTPUTS
        [pscustomobject] Techniques (T####) and SubTechniques (T####.###).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)] $Rule)

    $p = $Rule.properties
    $raw = @()
    foreach ($name in 'techniques', 'subTechniques') {
        if ($p -and $p.PSObject.Properties.Name -contains $name) { $raw += @($p.$name) }
    }
    $ids = @($raw | Where-Object { $_ } | ForEach-Object { ([string]$_).Trim().ToUpperInvariant() } | Where-Object { $_ -match '^T\d{4}(\.\d{3})?$' })
    $subs = @($ids | Where-Object { $_ -match '\.' } | Sort-Object -Unique)
    $bases = @(@($ids | Where-Object { $_ -notmatch '\.' }) + @($subs | ForEach-Object { ($_ -split '\.')[0] }) | Sort-Object -Unique)
    [pscustomobject]@{ Techniques = $bases; SubTechniques = $subs }
}

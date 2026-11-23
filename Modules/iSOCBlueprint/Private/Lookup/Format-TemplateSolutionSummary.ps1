#Requires -Version 7.6

<#
.SYNOPSIS
    A short line of the solutions a set of templates come from, with how many each and whether installed

.DESCRIPTION
    One of the helpers beside Get-TemplateSolution.ps1, which describes the whole.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Lookup/Format-TemplateSolutionSummary.ps1
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

function Format-TemplateSolutionSummary {
    <#
    .SYNOPSIS
        A short line of the solutions a set of templates come from, with how
        many each and whether installed: "Microsoft Entra ID (12, installed);
        Azure Activity (3); Built-in (2)". Installed first, then by count.

    .PARAMETER Templates
        Template references (TemplateId).

    .PARAMETER Map
        From Get-TemplateSolutionMap.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowNull()] [AllowEmptyCollection()] [object[]] $Templates, [AllowNull()] [hashtable] $Map)

    $groups = @{}
    foreach ($t in @($Templates)) {
        if (-not $t) { continue }
        $s = Get-TemplateSolution -Map $Map -TemplateId ([string]$t.TemplateId)
        if (-not $groups.ContainsKey($s.Solution)) { $groups[$s.Solution] = [pscustomobject]@{ Solution = $s.Solution; Installed = $s.Installed; Count = 0 } }
        $groups[$s.Solution].Count++
    }
    $ordered = @(
        $groups.Values |
            Sort-Object @{
                Expression = { if ($_.Installed -eq $true) { 0 } elseif ($_.Installed -eq $false) { 1 } else { 2 } }
            }, @{ Expression = 'Count'; Descending = $true }, Solution
    )
    return (($ordered | ForEach-Object { "$($_.Solution) ($($_.Count)$(if ($_.Installed -eq $true) { ', installed' }))" }) -join '; ')
}

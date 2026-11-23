#Requires -Version 7.6

<#
.SYNOPSIS
    A count and its noun, singular or plural as the count needs: 1 table, 3 tables, 1,250 tables. Never table(s).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Format/Text/Format-BlueprintPlural.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.1.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Blueprint text formatting
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Format-BlueprintPlural {
    <#
    .SYNOPSIS
        A count and its noun, singular or plural as the count needs:
        1 table, 3 tables, 1,250 tables. Never table(s).

    .PARAMETER Count
        The count.

    .PARAMETER Singular
        The noun for one (table, rule, policy).

    .PARAMETER Plural
        The noun for any other count. Defaults to the singular plus 's'.

    .PARAMETER NoCount
        The noun alone, chosen by the count (for "the table" or "the
        tables" after a figure already given).

    .OUTPUTS
        [string]
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param([AllowNull()] $Count, [Parameter(Mandatory)] [string] $Singular, [string] $Plural, [switch] $NoCount)
    $n = ConvertTo-BlueprintDouble $Count
    if ($null -eq $n) { $n = 0 }
    $word = if ($n -eq 1) { $Singular } elseif ($Plural) { $Plural } else { "${Singular}s" }
    if ($NoCount) { return $word }
    "$(Format-BlueprintCount $n) $word"
}

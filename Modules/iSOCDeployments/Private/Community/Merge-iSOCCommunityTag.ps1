#Requires -Version 7.2

<#
.SYNOPSIS
    A community rule's tags with the source's own added.

.DESCRIPTION
    Copied from Merge-Tags (Tools/Import-CommunityRules.ps1).

.NOTES
    File:         Modules/iSOCDeployments/Private/Community/Merge-iSOCCommunityTag.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.0
    Last Updated: 2026-11-04
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Merge-iSOCCommunityTag {
    <#
    .SYNOPSIS
        Return the rule's tags and the required ones, each once in any
        case, sorted.

    .PARAMETER Existing
        The rule's tags: a list, one string, or nothing.

    .PARAMETER Required
        The tags every rule of the source gets.

    .OUTPUTS
        [string] One tag each.

    .EXAMPLE
        Merge-iSOCCommunityTag -Existing $rule.tags -Required $source.Tags
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [object] $Existing,

        [string[]] $Required = @()
    )

    $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if ($Existing -is [System.Collections.IEnumerable] -and $Existing -isnot [string]) {
        foreach ($tag in $Existing) { [void]$set.Add($tag.ToString()) }
    }
    elseif ($Existing -is [string] -and $Existing -ne '') {
        [void]$set.Add($Existing)
    }
    foreach ($tag in $Required) { [void]$set.Add($tag) }
    @($set | Sort-Object)
}

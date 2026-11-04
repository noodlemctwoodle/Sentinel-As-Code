#Requires -Version 7.2

<#
.SYNOPSIS
    The ids an import must not give a community rule.

.DESCRIPTION
    Copied from Get-ReservedRuleId (Tools/Import-CommunityRules.ps1).

.NOTES
    File:         Modules/iSOCDeployments/Private/Community/Get-iSOCReservedRuleId.ps1
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

function Get-iSOCReservedRuleId {
    <#
    .SYNOPSIS
        Return the ids of the rule files under a rules folder, outside the
        folder being imported into, with where each is.

    .DESCRIPTION
        These are the in-house rules' ids and every other contributor's.
        Keys compare without regard to case, as the workspace does; the
        first file with an id keeps it.

    .PARAMETER RulesRoot
        Content/AnalyticalRules.

    .PARAMETER ExcludePath
        The folder the import writes to.

    .OUTPUTS
        [hashtable] The path, relative to the rules folder, by id.

    .EXAMPLE
        Get-iSOCReservedRuleId -RulesRoot $rules -ExcludePath $output
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $RulesRoot,

        [Parameter(Mandatory)]
        [string] $ExcludePath
    )

    $ids = @{}
    if (-not (Test-Path -LiteralPath $RulesRoot -PathType Container)) { return $ids }
    $separator = [System.IO.Path]::DirectorySeparatorChar
    $exclude = [System.IO.Path]::GetFullPath($ExcludePath).TrimEnd('/', '\') + $separator
    foreach ($file in Get-ChildItem -LiteralPath $RulesRoot -Recurse -File -Include '*.yaml', '*.yml') {
        if ($file.FullName.StartsWith($exclude, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        $id = Get-iSOCRuleFileId -Path $file.FullName
        if ($id -and -not $ids.ContainsKey($id)) { $ids[$id] = [System.IO.Path]::GetRelativePath($RulesRoot, $file.FullName).Replace('\', '/') }
    }
    $ids
}

#Requires -Version 7.6

<#
.SYNOPSIS
    A rule id as the rules-fired capture and the dashboard key it.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Helpers/Conversion/ConvertTo-GapRuleKey.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Gap Engine
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.
function ConvertTo-GapRuleKey {
    <#
    .SYNOPSIS
        A rule id as the rules-fired capture and the dashboard key it.

    .DESCRIPTION
        The id is trimmed, lower-cased and stripped of braces. When it arrives
        as a resource path, only the last segment is kept.

    .PARAMETER Value
        The rule id, or the resource path ending in it.

    .OUTPUTS
        [string]
    #>
    [CmdletBinding()]
    param([object]$Value)
    $k = ([string]$Value).Trim().ToLowerInvariant().Trim('{', '}')
    if ($k -match '/') { $k = ($k -split '/')[-1].Trim('{', '}') }
    return $k
}

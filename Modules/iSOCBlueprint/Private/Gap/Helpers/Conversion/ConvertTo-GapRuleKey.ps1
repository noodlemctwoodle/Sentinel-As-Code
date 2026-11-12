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
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, Gap Engine
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# A rule id as the rules-fired capture and the dashboard key it: lower case,
# braces off, the last segment when it arrives as a resource path.
function ConvertTo-GapRuleKey {
    param([object]$Value)
    $k = ([string]$Value).Trim().ToLowerInvariant().Trim('{', '}')
    if ($k -match '/') { $k = ($k -split '/')[-1].Trim('{', '}') }
    return $k
}

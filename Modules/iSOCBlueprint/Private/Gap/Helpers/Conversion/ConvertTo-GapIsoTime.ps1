#Requires -Version 7.6

<#
.SYNOPSIS
    A timestamp as ISO-8601 UTC text, whichever shape arrives.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Helpers/Conversion/ConvertTo-GapIsoTime.ps1
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

# ConvertFrom-Json turns ISO-8601 strings into DateTime; keep timestamps
# in evidence text as ISO-8601 UTC whichever shape arrives.
function ConvertTo-GapIsoTime {
    param([object]$Value)
    if ($null -eq $Value) { return '' }
    if ($Value -is [datetime]) { return $Value.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }
    return [string]$Value
}

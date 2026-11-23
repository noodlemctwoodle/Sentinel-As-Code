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
    Version:      0.1.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Gap Engine
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.
function ConvertTo-GapIsoTime {
    <#
    .SYNOPSIS
        A timestamp as ISO-8601 UTC text, whichever shape arrives.

    .DESCRIPTION
        ConvertFrom-Json turns ISO-8601 strings into DateTime, so a timestamp
        arrives as either a DateTime or text. A DateTime is converted to UTC
        and formatted yyyy-MM-ddTHH:mm:ssZ, any other value comes back as its
        text, and $null gives an empty string.

    .PARAMETER Value
        The timestamp to format.

    .OUTPUTS
        [string]
    #>
    [CmdletBinding()]
    param([object]$Value)
    if ($null -eq $Value) { return '' }
    if ($Value -is [datetime]) { return $Value.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }
    return [string]$Value
}

#Requires -Version 7.6

<#
.SYNOPSIS
    A number of days as "1 day" or "N days".

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Helpers/Window/Format-GapDays.ps1
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
function Format-GapDays {
    <#
    .SYNOPSIS
        A number of days as "1 day" or "N days".

    .PARAMETER Days
        The number of days.

    .OUTPUTS
        [string]
    #>
    [CmdletBinding()]
    param([int]$Days)
    if ($Days -eq 1) { '1 day' } else { "$Days days" }
}

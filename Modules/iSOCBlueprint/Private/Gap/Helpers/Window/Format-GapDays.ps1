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
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, Gap Engine
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# "1 day" or "N days".
function Format-GapDays([int]$Days) { if ($Days -eq 1) { '1 day' } else { "$Days days" } }

#Requires -Version 7.6

<#
.SYNOPSIS
    One wording or the other by a count, such as has or have.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Helpers/Wording/Select-GapWording.ps1
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

# One wording or the other by the count: Select-GapWording 1 'has' 'have' reads has.
function Select-GapWording { param($Count, [string]$One, [string]$Many) if ((ConvertTo-BlueprintDouble $Count) -eq 1) { $One } else { $Many } }

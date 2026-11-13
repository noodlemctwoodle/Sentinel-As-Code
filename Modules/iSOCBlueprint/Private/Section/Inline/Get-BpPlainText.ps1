#Requires -Version 7.6

<#
.SYNOPSIS
    Get-BpPlainText

.NOTES
    File:         Modules/iSOCBlueprint/Private/Section/Inline/Get-BpPlainText.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-13
    Version:      0.1.0
    Last Updated: 2026-11-13
    Component:    iSOC Blueprint, Section model conversion
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function Get-BpPlainText {
    <#
    .SYNOPSIS
        Plain text of a list of runs; a break becomes a space.
    #>
    param([object[]] $Runs)
    return ((@($Runs) | ForEach-Object { if ($_.Contains('text')) { $_.text } else { ' ' } }) -join '').Trim()
}

#Requires -Version 7.6

<#
.SYNOPSIS
    Join a list of runs into their plain text, with a break read as a space

.NOTES
    File:         Modules/iSOCBlueprint/Private/Section/Inline/Get-BpPlainText.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-13
    Version:      0.1.2
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Section model conversion
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-BpPlainText {
    <#
    .SYNOPSIS
        Join a list of runs into their plain text, with a break read as a space.

    .DESCRIPTION
        The joined text is trimmed.

    .PARAMETER Runs
        The runs: dictionaries holding text, or a break.

    .OUTPUTS
        [string] The text.
    #>
    [CmdletBinding()]
    param([object[]] $Runs)
    return ((@($Runs) | ForEach-Object { if ($_.Contains('text')) { $_.text } else { ' ' } }) -join '').Trim()
}

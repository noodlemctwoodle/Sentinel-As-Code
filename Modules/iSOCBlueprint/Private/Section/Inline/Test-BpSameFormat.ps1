#Requires -Version 7.6

<#
.SYNOPSIS
    Test whether a run has the same formatting as a format table

.NOTES
    File:         Modules/iSOCBlueprint/Private/Section/Inline/Test-BpSameFormat.ps1
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

function Test-BpSameFormat {
    <#
    .SYNOPSIS
        Test whether a run has the same formatting as a format table.

    .DESCRIPTION
        Compares bold, italic, code and strike as booleans and href as a string.
        An entry that is missing counts as false, or as an empty string for href.

    .PARAMETER Run
        The run: a dictionary that may hold bold, italic, code, strike and href.

    .PARAMETER Format
        The format hashtable to compare the run with.

    .OUTPUTS
        [bool] $true when all five entries match.
    #>
    [CmdletBinding()]
    param([System.Collections.IDictionary] $Run, [hashtable] $Format)
    foreach ($flag in 'bold', 'italic', 'code', 'strike') { if ([bool]$Run[$flag] -ne [bool]$Format[$flag]) { return $false } }
    return [string]$Run['href'] -eq [string]$Format['href']
}

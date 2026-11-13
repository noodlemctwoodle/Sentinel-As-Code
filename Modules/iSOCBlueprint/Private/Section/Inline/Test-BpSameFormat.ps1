#Requires -Version 7.6

<#
.SYNOPSIS
    Test-BpSameFormat

.NOTES
    File:         Modules/iSOCBlueprint/Private/Section/Inline/Test-BpSameFormat.ps1
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

function Test-BpSameFormat {
    param([System.Collections.IDictionary] $Run, [hashtable] $Format)
    foreach ($flag in 'bold', 'italic', 'code', 'strike') { if ([bool]$Run[$flag] -ne [bool]$Format[$flag]) { return $false } }
    return [string]$Run['href'] -eq [string]$Format['href']
}

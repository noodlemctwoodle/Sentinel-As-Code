#Requires -Version 7.6

<#
.SYNOPSIS
    Add-BpRun

.NOTES
    File:         Modules/iSOCBlueprint/Private/Section/Inline/Add-BpRun.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-13
    Version:      0.1.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Section model conversion
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Add-BpRun {
    param([System.Collections.Generic.List[object]] $Out, [string] $Text, [hashtable] $Format)
    if ($Text -eq '') { return }
    $last = if ($Out.Count) { $Out[$Out.Count - 1] } else { $null }
    if ($last -and $last.Contains('text') -and (Test-BpSameFormat $last $Format)) { $last.text += $Text; return }
    $run = [ordered]@{ text = $Text }
    foreach ($flag in 'bold', 'italic', 'code', 'strike') { if ($Format[$flag]) { $run[$flag] = $true } }
    if ($Format.href) { $run.href = $Format.href; $run.target = Get-BpLinkTarget $Format.href }
    $Out.Add($run)
}

#Requires -Version 7.6

<#
.SYNOPSIS
    Append a text run to a list of runs, merging it into the last run when the formatting matches

.NOTES
    File:         Modules/iSOCBlueprint/Private/Section/Inline/Add-BpRun.ps1
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

function Add-BpRun {
    <#
    .SYNOPSIS
        Append a text run to a list of runs, merging it into the last run when
        the formatting matches.

    .DESCRIPTION
        Empty text adds nothing. The last run absorbs the text when it is a text
        run with the same formatting (Test-BpSameFormat). Otherwise a new run is
        added, holding the text, each of bold, italic, code and strike that is
        set in Format and, when Format has an href, that href and its target
        from Get-BpLinkTarget.

    .PARAMETER Out
        The list of runs to append to.

    .PARAMETER Text
        The text of the run. An empty string adds nothing.

    .PARAMETER Format
        The formatting the run takes: a hashtable that may hold bold, italic,
        code, strike and href.
    #>
    [CmdletBinding()]
    param([System.Collections.Generic.List[object]] $Out, [string] $Text, [hashtable] $Format)
    if ($Text -eq '') { return }
    $last = if ($Out.Count) { $Out[$Out.Count - 1] } else { $null }
    if ($last -and $last.Contains('text') -and (Test-BpSameFormat $last $Format)) { $last.text += $Text; return }
    $run = [ordered]@{ text = $Text }
    foreach ($flag in 'bold', 'italic', 'code', 'strike') { if ($Format[$flag]) { $run[$flag] = $true } }
    if ($Format.href) { $run.href = $Format.href; $run.target = Get-BpLinkTarget $Format.href }
    $Out.Add($run)
}

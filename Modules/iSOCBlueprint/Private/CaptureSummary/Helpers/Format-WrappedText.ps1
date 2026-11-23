#Requires -Version 7.6

<#
.SYNOPSIS
    Text wrapped to a width under a hanging indent, one string a line.

.NOTES
    File:         Modules/iSOCBlueprint/Private/CaptureSummary/Helpers/Format-WrappedText.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.1.2
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Capture reporting
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Format-WrappedText {
    <#
    .SYNOPSIS
        Text wrapped to a width under a hanging indent, one string a line.

    .PARAMETER Text
        The text to wrap. Runs of whitespace separate its words.

    .PARAMETER Indent
        The number of spaces put before every line, which also narrows the
        room for text. 0 when omitted.

    .PARAMETER Width
        The full line width, indent included. 0 takes the console's, or 120
        where there is no console (a pipeline agent).
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [AllowEmptyString()] [string] $Text,
        [int] $Indent = 0,
        [int] $Width = 0
    )

    if ($Width -le 0) {
        $Width = try { [int]$Host.UI.RawUI.WindowSize.Width } catch { 0 }
        if ($Width -lt 40) { $Width = 120 }
    }
    $room = [math]::Max(30, $Width - $Indent - 1)
    $pad = ' ' * $Indent
    $lines = [System.Collections.Generic.List[string]]::new()
    $line = ''
    foreach ($word in @($Text -split '\s+' | Where-Object { $_ })) {
        if ($line.Length -gt 0 -and $line.Length + 1 + $word.Length -gt $room) {
            $lines.Add("$pad$line")
            $line = $word
        } else {
            $line = if ($line) { "$line $word" } else { $word }
        }
    }
    if ($line) { $lines.Add("$pad$line") }
    $lines.ToArray()
}

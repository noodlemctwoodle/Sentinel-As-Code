#Requires -Version 7.6

<#
.SYNOPSIS
    A short hash of a Mermaid chart's body, used to name its image file.

.NOTES
    File:         Modules/iSOCBlueprint/Private/ChartImage/Get-MermaidHash.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.1.0
    Last Updated: 2026-11-16
    Component:    iSOC Blueprint, chart images
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function Get-MermaidHash {
    <#
    .SYNOPSIS
        The first 12 characters of the SHA-256 hash of a chart's text, in
        lower case.

    .PARAMETER Text
        The Mermaid body, without its fence.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string] $Text)

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hex = [System.BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', ''
    }
    finally { $sha.Dispose() }
    return $hex.Substring(0, 12).ToLower()
}

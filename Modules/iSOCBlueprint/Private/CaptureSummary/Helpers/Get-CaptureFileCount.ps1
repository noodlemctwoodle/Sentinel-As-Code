#Requires -Version 7.6

<#
.SYNOPSIS
    Items in one _raw file: rows for an array file, 1 or 0 for a single object. $null when the file is missing, -1 when it does not parse.

.NOTES
    File:         Modules/iSOCBlueprint/Private/CaptureSummary/Helpers/Get-CaptureFileCount.ps1
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

function Get-CaptureFileCount {
    <#
    .SYNOPSIS
        Items in one _raw file: rows for an array file, 1 or 0 for a single
        object. $null when the file is missing, -1 when it does not parse.

    .PARAMETER Path
        The _raw JSON file to count.
    #>
    [OutputType([int])]
    [CmdletBinding()]
    param([string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = Get-Content -LiteralPath $Path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) { return 0 }
    try { $parsed = $raw | ConvertFrom-Json -ErrorAction Stop } catch { return -1 }
    if ($raw.TrimStart().StartsWith('{')) {
        if ($null -eq $parsed -or @($parsed.PSObject.Properties).Count -eq 0) { return 0 }
        return 1
    }
    if ($null -eq $parsed) { return 0 }
    @($parsed).Count
}

#Requires -Version 7.6

<#
.SYNOPSIS
    Read a JSON file the estimate uses, or $null when it is missing or empty.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Cost/Helpers/Read-CostJson.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.1.0
    Last Updated: 2026-11-16
    Component:    iSOC Blueprint, cost estimate
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Read-CostJson {
    <#
    .SYNOPSIS
        Read a JSON file the estimate uses, or $null when it is missing or empty.

    .PARAMETER Path
        The JSON file.

    .OUTPUTS
        The parsed document, or $null.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)

    if (-not (Test-Path $Path)) { return $null }
    $raw = Get-Content $Path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json -Depth 32)
}

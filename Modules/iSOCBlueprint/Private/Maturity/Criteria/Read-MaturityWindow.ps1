#Requires -Version 7.6

<#
.SYNOPSIS
    The window the KQL captures read, from run-context.json.

.DESCRIPTION
    A run collected before the setting existed read 30 days and its recent
    figures 7, which is also the result when the file is absent.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Maturity/Criteria/Read-MaturityWindow.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.2
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Maturity Engine
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Read-MaturityWindow {
    <#
    .SYNOPSIS
        The lookback and recent days the KQL captures read.

    .PARAMETER InputRoot
        The _raw folder.

    .OUTPUTS
        [pscustomobject] with Days and RecentDays.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory = $true)] [string] $InputRoot)

    $window = [pscustomobject]@{ Days = 30; RecentDays = 7 }
    $runContextPath = Join-Path $InputRoot 'run-context.json'
    if (Test-Path $runContextPath) {
        $rc = Get-Content $runContextPath -Raw | ConvertFrom-Json
        if ($rc -and $rc.PSObject.Properties['LookbackDays'] -and [int]$rc.LookbackDays -ge 1) {
            $window.Days = [int]$rc.LookbackDays
            $window.RecentDays = [math]::Min(7, $window.Days)
        }
        if ($rc -and $rc.PSObject.Properties['RecentDays'] -and [int]$rc.RecentDays -ge 1) { $window.RecentDays = [int]$rc.RecentDays }
    }
    return $window
}

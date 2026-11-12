#Requires -Version 7.6

<#
.SYNOPSIS
    Build a finding object (Evidence and Detail) in the one shape every check returns.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Helpers/Finding/New-Finding.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, Gap Engine
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Helper, produces a Finding object with consistent shape.
function New-Finding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Evidence,
        [Parameter(Mandatory = $false)]
        [object]$Detail = $null
    )
    [pscustomobject]@{
        Evidence = $Evidence
        Detail   = $Detail
    }
}

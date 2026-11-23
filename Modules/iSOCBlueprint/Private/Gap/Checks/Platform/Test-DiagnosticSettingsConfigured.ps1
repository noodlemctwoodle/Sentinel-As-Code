#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-PLT-08: Diagnostic settings not configured

.DESCRIPTION
    Gap check for rule SAC-PLT-08 (Resources/Data/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Platform/Test-DiagnosticSettingsConfigured.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.2
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Gap Engine
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# ------------------------------------------------------------
# SAC-PLT-08, Diagnostic settings not configured
# ------------------------------------------------------------
function Test-DiagnosticSettingsConfigured {
    <#
    .SYNOPSIS
        Gap check SAC-PLT-08: Diagnostic settings not configured

    .PARAMETER Inventory
        The inventory Get-SentinelGap builds from the raw files.

    .OUTPUTS
        $null when the rule passes; otherwise the finding New-Finding returns, with its
        Evidence and Detail.
    #>
    [CmdletBinding()] param([Parameter(Mandatory = $true)]$Inventory)
    if (-not $Inventory.DiagnosticSettings -or @($Inventory.DiagnosticSettings).Count -eq 0) {
        return New-Finding -Evidence 'No diagnostic settings configured on the Log Analytics workspace.'
    }
    return $null
}

#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-PLT-03: MMA / OMS / Log Analytics agent still heartbeating

.DESCRIPTION
    Gap check for rule SAC-PLT-03 (Resources/Data/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Platform/Test-MmaAgentStillHeartbeating.ps1
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
# SAC-PLT-03, MMA / OMS / Log Analytics agent still heartbeating
# ------------------------------------------------------------
function Test-MmaAgentStillHeartbeating {
    <#
    .SYNOPSIS
        Gap check SAC-PLT-03: MMA / OMS / Log Analytics agent still heartbeating

    .PARAMETER Inventory
        The inventory Get-SentinelGap builds from the raw files.

    .OUTPUTS
        $null when the rule passes; otherwise the finding New-Finding returns, with its
        Evidence and Detail.
    #>
    [CmdletBinding()] param([Parameter(Mandatory = $true)]$Inventory)
    if (-not $Inventory.AmaMmaMigration -or @($Inventory.AmaMmaMigration).Count -eq 0) { return $null }
    $mmaTotal = 0
    foreach ($row in $Inventory.AmaMmaMigration) {
        $mma = [int](Get-PropOrDefault $row 'MMACount' 0)
        if ($mma -gt 0) { $mmaTotal += $mma }
    }
    if ($mmaTotal -eq 0) { return $null }
    return New-Finding -Evidence "$(Format-BlueprintPlural $mmaTotal 'machine') still heartbeating via the legacy Log Analytics agent (MMA / OMS). MMA retired on 31 Aug 2024; ingestion is degraded after 1 Feb 2025." -Detail @{ MmaCount = $mmaTotal }
}

#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-INC-06: Incident MTTR above 24h

.DESCRIPTION
    Gap check for rule SAC-INC-06 (Resources/Data/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Incidents/Test-IncidentMttrThreshold.ps1
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
# SAC-INC-06, Incident MTTR above 24h
# ------------------------------------------------------------
function Test-IncidentMttrThreshold {
    <#
    .SYNOPSIS
        Gap check SAC-INC-06: Incident MTTR above 24h

    .PARAMETER Inventory
        The inventory Get-SentinelGap builds from the raw files.

    .OUTPUTS
        $null when the rule passes; otherwise the finding New-Finding returns, with its
        Evidence and Detail.
    #>
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    if (-not $Inventory.IncidentsMttr -or @($Inventory.IncidentsMttr).Count -eq 0) { return $null }
    $row = $Inventory.IncidentsMttr[0]
    $closed = [int](Get-PropOrDefault $row 'ClosedCount' 0)
    if ($closed -eq 0) { return $null }
    $mttrRaw = Get-PropOrDefault $row 'MTTRMinutes' $null
    $mttr = 0.0
    if (-not [double]::TryParse([string]$mttrRaw, [ref]$mttr)) { return $null }
    if ($mttr -le 1440.0) { return $null }
    $hours = [math]::Round($mttr / 60.0, 1)
    return New-Finding -Evidence "MTTR over the last $(Format-GapDays (Get-GapWindow $Inventory).Days) is $(Format-BlueprintNumber $hours -Decimals 1) hours across $(Format-BlueprintPlural $closed 'closed incident'); SOC target is 24 hours or less." -Detail @{ MttrHours = $hours; ClosedCount = $closed }
}

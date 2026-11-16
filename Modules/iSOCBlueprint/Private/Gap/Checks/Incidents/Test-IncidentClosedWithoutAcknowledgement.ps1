#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-INC-05: Majority of incidents closed without ever being acknowledged

.DESCRIPTION
    Gap check for rule SAC-INC-05 (Resources/Data/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Incidents/Test-IncidentClosedWithoutAcknowledgement.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-16
    Component:    iSOC Blueprint, Gap Engine
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# ------------------------------------------------------------
# SAC-INC-05, Majority of incidents closed without ever being acknowledged
# ------------------------------------------------------------
function Test-IncidentClosedWithoutAcknowledgement {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    if (-not $Inventory.IncidentsMttr -or @($Inventory.IncidentsMttr).Count -eq 0) { return $null }
    $row = $Inventory.IncidentsMttr[0]
    $closed = [int](Get-PropOrDefault $row 'ClosedCount' 0)
    # The AcknowledgedCount column was added by a recent fix; on older
    # capture files it isn't present and the check has nothing to evaluate.
    if ($row.PSObject.Properties.Name -notcontains 'AcknowledgedCount') { return $null }
    $ack = [int](Get-PropOrDefault $row 'AcknowledgedCount' 0)
    if ($closed -lt 10) { return $null }            # statistical floor, small samples lie
    $unack = $closed - $ack
    $ratio = $unack / [double]$closed
    if ($ratio -le 0.5) { return $null }
    return New-Finding -Evidence "$(Format-BlueprintCount $unack) of $(Format-BlueprintCount $closed) closed incidents ($([math]::Round($ratio*100,0))%) never reached an acknowledged state. Automation is auto-closing without analyst review, or analytics rules are flooding the queue." -Detail @{ Closed = $closed; Acknowledged = $ack; Unacknowledged = $unack }
}

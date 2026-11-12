#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-DET-11: Single rule producing > 30% of alert volume

.DESCRIPTION
    Gap check for rule SAC-DET-11 (Resources/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Detection/Test-DominantNoisyRule.ps1
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

# ------------------------------------------------------------
# SAC-DET-11, Single rule producing > 30% of alert volume
# ------------------------------------------------------------
function Test-DominantNoisyRule {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    if (-not $Inventory.AnalyticsRuleVolumes -or @($Inventory.AnalyticsRuleVolumes).Count -eq 0) { return $null }
    $rows = @($Inventory.AnalyticsRuleVolumes)
    $totalAlerts = ($rows | ForEach-Object { [double](Get-PropOrDefault $_ 'Alerts' 0) } | Measure-Object -Sum).Sum
    if (-not $totalAlerts -or $totalAlerts -lt 100) { return $null }   # too quiet to draw conclusions
    $top = $rows | Sort-Object -Property @{ Expression = { [double](Get-PropOrDefault $_ 'Alerts' 0) } } -Descending | Select-Object -First 1
    $topAlerts = [double](Get-PropOrDefault $top 'Alerts' 0)
    $ratio = $topAlerts / [double]$totalAlerts
    if ($ratio -le 0.30) { return $null }
    $name = Get-EvidenceName $top 'AlertName' 'Unnamed alert'
    return New-Finding -Evidence "Rule `"$name`" produced $(Format-BlueprintCount $topAlerts) of $(Format-BlueprintCount $totalAlerts) alerts in the last $(Format-GapDays (Get-GapWindow $Inventory).Days) ($([math]::Round($ratio*100,0))%), tuning candidate." -Detail @{ AlertName = $name; Alerts = [int]$topAlerts; Total = [int]$totalAlerts; Ratio = $ratio }
}

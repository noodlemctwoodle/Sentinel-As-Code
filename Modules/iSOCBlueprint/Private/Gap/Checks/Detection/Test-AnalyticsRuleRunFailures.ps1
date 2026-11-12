#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-DET-14: Analytics rule runs are failing (SentinelHealth, last 7 days)

.DESCRIPTION
    Gap check for rule SAC-DET-14 (Resources/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Detection/Test-AnalyticsRuleRunFailures.ps1
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
# SAC-DET-14, Analytics rule runs are failing (SentinelHealth, last 7 days)
# ------------------------------------------------------------
function Test-AnalyticsRuleRunFailures {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    if (@($Inventory.RuleHealth).Count -eq 0) { return $null }
    $failing = @($Inventory.RuleHealth | Where-Object {
        $null -ne $_ -and (ConvertTo-GapInt (Get-PropOrDefault $_ 'Failures' 0)) -gt 0
    } | Sort-Object { -(ConvertTo-GapInt (Get-PropOrDefault $_ 'Failures' 0)) })
    if ($failing.Count -eq 0) { return $null }
    $sample = ($failing | ForEach-Object {
        $reason = [string](Get-PropOrDefault $_ 'Reason' '')
        $why = if ($reason) { ": $reason" } else { '' }
        "$(Get-EvidenceName $_ 'RuleName' 'Unnamed rule') ($(Format-BlueprintPlural (ConvertTo-GapInt (Get-PropOrDefault $_ 'Failures' 0)) 'failed run')$why)"
    }) -join '; '
    return New-Finding -Evidence "$(Format-BlueprintPlural $failing.Count 'analytics rule') had failed runs in the last $(Format-GapDays (Get-GapWindow $Inventory).Days): $sample." -Detail @{
        Count = $failing.Count
        Rules = @($failing | ForEach-Object {
            [pscustomobject]@{
                RuleName    = [string](Get-PropOrDefault $_ 'RuleName' '')
                Status      = [string](Get-PropOrDefault $_ 'Status' '')
                Failures    = ConvertTo-GapInt (Get-PropOrDefault $_ 'Failures' 0)
                LastFailure = ConvertTo-GapIsoTime (Get-PropOrDefault $_ 'LastFailure' $null)
                Reason      = [string](Get-PropOrDefault $_ 'Reason' '')
            }
        })
    }
}

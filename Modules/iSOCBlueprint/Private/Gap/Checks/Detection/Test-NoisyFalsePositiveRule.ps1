#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-DET-06: Analytics rule closes mostly as false positive

.DESCRIPTION
    Gap check for rule SAC-DET-06 (Resources/Data/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Detection/Test-NoisyFalsePositiveRule.ps1
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
# SAC-DET-06, Analytics rule closes mostly as false positive
# ------------------------------------------------------------
function Test-NoisyFalsePositiveRule {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    if (@($Inventory.RuleEffectiveness).Count -eq 0) { return $null }
    # Sentinel rules only (rows with an AlertRuleId); alerts from other
    # products are tuned in their own portal, not in a rule's query.
    # Statistical floor of 20 closed incidents so a handful of closures
    # cannot condemn a rule.
    $noisy = @($Inventory.RuleEffectiveness | Where-Object {
        $null -ne $_ -and
        -not [string]::IsNullOrWhiteSpace([string](Get-PropOrDefault $_ 'AlertRuleId' '')) -and
        (ConvertTo-GapInt (Get-PropOrDefault $_ 'Closed' 0)) -ge 20 -and
        (ConvertTo-GapDouble (Get-PropOrDefault $_ 'FPRate' 0)) -gt 70
    } | Sort-Object { -(ConvertTo-GapDouble (Get-PropOrDefault $_ 'FPRate' 0)) })
    if ($noisy.Count -eq 0) { return $null }
    $sample = ($noisy | ForEach-Object {
        "$(Get-EvidenceName $_ 'RuleName' 'Unnamed rule') ($(Format-BlueprintCount (ConvertTo-GapInt (Get-PropOrDefault $_ 'FalsePositive' 0))) of $(Format-BlueprintCount (ConvertTo-GapInt (Get-PropOrDefault $_ 'Closed' 0))) closed as false positive, $(Format-BlueprintNumber (ConvertTo-GapDouble (Get-PropOrDefault $_ 'FPRate' 0)) -Decimals 1)%)"
    }) -join '; '
    return New-Finding -Evidence "$(Format-BlueprintPlural $noisy.Count 'rule') closed mostly as false positive in the last $(Format-GapDays (Get-GapWindow $Inventory).Days): $sample." -Detail @{
        Count = $noisy.Count
        Rules = @($noisy | ForEach-Object {
            [pscustomobject]@{
                RuleName      = [string](Get-PropOrDefault $_ 'RuleName' '')
                AlertRuleId   = [string](Get-PropOrDefault $_ 'AlertRuleId' '')
                Closed        = ConvertTo-GapInt (Get-PropOrDefault $_ 'Closed' 0)
                FalsePositive = ConvertTo-GapInt (Get-PropOrDefault $_ 'FalsePositive' 0)
                FPRate        = ConvertTo-GapDouble (Get-PropOrDefault $_ 'FPRate' 0)
            }
        })
    }
}

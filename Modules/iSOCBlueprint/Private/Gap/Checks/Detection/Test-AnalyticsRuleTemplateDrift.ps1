#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-DET-10: Deployed rule's templateVersion lags the latest template

.DESCRIPTION
    Gap check for rule SAC-DET-10 (Resources/Data/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Detection/Test-AnalyticsRuleTemplateDrift.ps1
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
# SAC-DET-10, Deployed rule's templateVersion lags the latest template
# ------------------------------------------------------------
function Test-AnalyticsRuleTemplateDrift {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    if (-not $Inventory.AlertRules -or -not $Inventory.AlertRuleTemplates) { return $null }
    $latestByTemplate = @{}
    foreach ($t in $Inventory.AlertRuleTemplates) {
        $tname = Get-PropOrDefault $t 'name' ''
        $v = Get-PropOrDefault $t 'properties.version' $null
        if ($tname -and $v) { $latestByTemplate[$tname] = [string]$v }
    }
    if ($latestByTemplate.Count -eq 0) { return $null }
    $drifted = @()
    foreach ($r in $Inventory.AlertRules) {
        $tplName = Get-PropOrDefault $r 'properties.alertRuleTemplateName' $null
        if (-not $tplName) { continue }
        if (-not $latestByTemplate.ContainsKey($tplName)) { continue }
        $deployed = Get-PropOrDefault $r 'properties.templateVersion' $null
        if (-not $deployed) { continue }
        if ([string]$deployed -ne $latestByTemplate[$tplName]) {
            $drifted += [pscustomobject]@{
                Name     = Get-EvidenceName $r 'properties.displayName', 'name' 'Unnamed rule'
                Deployed = [string]$deployed
                Latest   = $latestByTemplate[$tplName]
            }
        }
    }
    if ($drifted.Count -eq 0) { return $null }
    $sample = ($drifted | ForEach-Object { "$($_.Name) ($($_.Deployed) to $($_.Latest))" }) -join '; '
    return New-Finding -Evidence "$(Format-BlueprintPlural $drifted.Count 'deployed rule') $(Select-GapWording $drifted.Count 'lags' 'lag') the latest template version: $sample." -Detail @{ Count = $drifted.Count }
}

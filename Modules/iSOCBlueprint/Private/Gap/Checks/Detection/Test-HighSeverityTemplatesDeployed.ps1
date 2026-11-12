#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-DET-09: High-severity templates not deployed

.DESCRIPTION
    Gap check for rule SAC-DET-09 (Resources/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Detection/Test-HighSeverityTemplatesDeployed.ps1
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
# SAC-DET-09, High-severity templates not deployed
# ------------------------------------------------------------
function Test-HighSeverityTemplatesDeployed {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    $deployedTemplateNames = @{}
    foreach ($r in @($Inventory.AlertRules)) {
        $tn = Get-PropOrDefault $r 'properties.alertRuleTemplateName' ''
        if ($tn) { $deployedTemplateNames[$tn] = $true }
    }
    $missing = @($Inventory.AlertRuleTemplates | Where-Object {
        $sev = Get-PropOrDefault $_ 'properties.severity' 'Low'
        $name = Get-PropOrDefault $_ 'name' ''
        ($sev -eq 'High') -and ($name) -and (-not $deployedTemplateNames.ContainsKey($name))
    })
    if ($missing.Count -gt 0) {
        return New-Finding -Evidence "$(Format-BlueprintPlural $missing.Count 'High-severity template') not deployed." -Detail @{ Count = $missing.Count }
    }
    return $null
}

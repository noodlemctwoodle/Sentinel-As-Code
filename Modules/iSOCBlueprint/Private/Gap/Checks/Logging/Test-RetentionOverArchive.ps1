#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-LOG-11: Long retention on Analytics rather than archive

.DESCRIPTION
    Gap check for rule SAC-LOG-11 (Resources/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Logging/Test-RetentionOverArchive.ps1
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
# SAC-LOG-11, Long retention on Analytics rather than archive
# ------------------------------------------------------------
function Test-RetentionOverArchive {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    $bad = @($Inventory.WorkspaceTables | Where-Object {
        $r = [int](Get-PropOrDefault $_ 'properties.retentionInDays' 0)
        $r -gt 90
    })
    if ($bad.Count -gt 0) {
        return New-Finding -Evidence "$(Format-BlueprintPlural $bad.Count 'table') $(Select-GapWording $bad.Count 'has' 'have') interactive retention of more than 90 days. Consider lowering retentionInDays and using totalRetentionInDays for archive." -Detail @{ Count = $bad.Count }
    }
    return $null
}

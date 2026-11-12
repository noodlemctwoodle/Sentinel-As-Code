#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-LOG-15: CommonSecurityLog volume warrants a vendor _CL split

.DESCRIPTION
    Gap check for rule SAC-LOG-15 (Resources/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Logging/Test-CefSplitOpportunity.ps1
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
# SAC-LOG-15, CommonSecurityLog volume warrants a vendor _CL split
# ------------------------------------------------------------
function Test-CefSplitOpportunity {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    $cef = @($Inventory.TablesWithData | Where-Object {
        (Get-PropOrDefault $_ 'DataType' '') -eq 'CommonSecurityLog'
    } | Select-Object -First 1)
    if ($cef.Count -eq 0) { return $null }
    $gb30 = Get-GapBillable30d $cef[0]
    if ((ConvertTo-GapPer30Days $gb30 $Inventory) -lt $script:DataRoutingSplitThresholdGb30d) { return $null }
    return New-Finding -Evidence "CommonSecurityLog ingested $(Format-BlueprintGb $gb30) GB in the last $(Format-GapDays (Get-GapWindow $Inventory).Days) at the Sentinel security-data rate, routine vendor records could split to a `<Vendor>_CL` custom table via a DCR filter+split transformation." -Detail @{ Gb30d = $gb30 }
}

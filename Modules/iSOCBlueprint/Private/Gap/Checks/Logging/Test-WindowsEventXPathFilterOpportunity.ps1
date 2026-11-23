#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-LOG-17: SecurityEvent / WindowsEvent XPath filter opportunity

.DESCRIPTION
    Gap check for rule SAC-LOG-17 (Resources/Data/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Logging/Test-WindowsEventXPathFilterOpportunity.ps1
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
# SAC-LOG-17, SecurityEvent / WindowsEvent XPath filter opportunity
# ------------------------------------------------------------
function Test-WindowsEventXPathFilterOpportunity {
    <#
    .SYNOPSIS
        Gap check SAC-LOG-17: SecurityEvent / WindowsEvent XPath filter opportunity

    .PARAMETER Inventory
        The inventory Get-SentinelGap builds from the raw files.

    .OUTPUTS
        $null when the rule passes; otherwise the finding New-Finding returns, with its
        Evidence and Detail.
    #>
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    # 5 GB / day across SecurityEvent + WindowsEvent is the trigger, the
    # AMA DCRs that ship Microsoft's own SecurityEvent collection ('All
    # Events') easily clear that on a domain controller, and the XPath
    # change is a documented, low-risk DCR edit.
    $tables = @('SecurityEvent','WindowsEvent','Event')
    $totalGb30 = 0.0
    foreach ($t in @($Inventory.TablesWithData)) {
        if ($tables -contains (Get-PropOrDefault $t 'DataType' '')) {
            $totalGb30 += Get-GapBillable30d $t
        }
    }
    if ((ConvertTo-GapPer30Days $totalGb30 $Inventory) -lt $script:DataRoutingSplitThresholdGb30d) { return $null }
    return New-Finding -Evidence "SecurityEvent/WindowsEvent ingested $(Format-BlueprintGb $totalGb30) GB in the last $(Format-GapDays (Get-GapWindow $Inventory).Days), typical AMA collection ships every Event ID. Add an XPath filter to drop 4624/4634/4672/5379 noise at the DCR." -Detail @{ Gb30d = $totalGb30 }
}

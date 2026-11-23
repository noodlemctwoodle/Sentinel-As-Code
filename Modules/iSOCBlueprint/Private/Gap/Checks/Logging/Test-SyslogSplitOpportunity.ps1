#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-LOG-16: Syslog volume warrants a facility-based DCR filter or _CL split

.DESCRIPTION
    Gap check for rule SAC-LOG-16 (Resources/Data/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Logging/Test-SyslogSplitOpportunity.ps1
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
# SAC-LOG-16, Syslog volume warrants a facility-based DCR filter or _CL split
# ------------------------------------------------------------
function Test-SyslogSplitOpportunity {
    <#
    .SYNOPSIS
        Gap check SAC-LOG-16: Syslog volume warrants a facility-based DCR filter or _CL split

    .PARAMETER Inventory
        The inventory Get-SentinelGap builds from the raw files.

    .OUTPUTS
        $null when the rule passes; otherwise the finding New-Finding returns, with its
        Evidence and Detail.
    #>
    [CmdletBinding()] param([Parameter(Mandatory = $true)]$Inventory)
    $sys = @($Inventory.TablesWithData | Where-Object {
            (Get-PropOrDefault $_ 'DataType' '') -eq 'Syslog'
        } | Select-Object -First 1)
    if ($sys.Count -eq 0) { return $null }
    $gb30 = Get-GapBillable30d $sys[0]
    if ((ConvertTo-GapPer30Day $gb30 $Inventory) -lt $script:DataRoutingSplitThresholdGb30d) { return $null }
    return New-Finding -Evidence "Syslog ingested $(Format-BlueprintGb $gb30) GB in the last $(Format-GapDay (Get-GapWindow $Inventory).Days), narrow the AMA DCR's facilityNames + logLevels to security-relevant facilities and route the rest to a custom _CL table at LA rates." -Detail @{ Gb30d = $gb30 }
}

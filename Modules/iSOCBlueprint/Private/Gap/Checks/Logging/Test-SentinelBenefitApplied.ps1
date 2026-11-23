#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-LOG-13: Sentinel benefit not detected

.DESCRIPTION
    Gap check for rule SAC-LOG-13 (Resources/Data/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Logging/Test-SentinelBenefitApplied.ps1
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
# SAC-LOG-13, Sentinel benefit not detected
# ------------------------------------------------------------
function Test-SentinelBenefitApplied {
    <#
    .SYNOPSIS
        Gap check SAC-LOG-13: Sentinel benefit not detected

    .PARAMETER Inventory
        The inventory Get-SentinelGap builds from the raw files.

    .OUTPUTS
        $null when the rule passes; otherwise the finding New-Finding returns, with its
        Evidence and Detail.
    #>
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    if (-not $Inventory.SentinelBenefitTables) { return $null }
    $eligible = $Inventory.SentinelBenefitTables.tables
    $billableSecurity = @($Inventory.TablesWithData | Where-Object {
        ($eligible -contains (Get-PropOrDefault $_ 'DataType' '')) -and
        ([double](Get-PropOrDefault $_ 'BillableLast30d' 0) -gt 0)
    })
    if ($billableSecurity.Count -gt 0) {
        $names = ($billableSecurity | Select-Object -ExpandProperty DataType) -join ', '
        return New-Finding -Evidence "Eligible security $(Select-GapWording $billableSecurity.Count 'table' 'tables') with non-zero billable ingest in the last $(Format-GapDays (Get-GapWindow $Inventory).Days): $names. If Defender plans are in force the benefit may not be applied." -Detail @{ Tables = $names }
    }
    return $null
}

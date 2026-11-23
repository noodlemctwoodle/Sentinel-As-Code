#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-INV-01: Silent tables (data in the lookback, none in the recent window)

.DESCRIPTION
    Gap check for rule SAC-INV-01 (Resources/Data/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Inventory/Test-SilentTables.ps1
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
# SAC-INV-01, Silent tables (data in the lookback, none in the recent window)
# ------------------------------------------------------------
function Test-SilentTables {
    <#
    .SYNOPSIS
        Gap check SAC-INV-01: Silent tables (data in the lookback, none in the recent window)

    .PARAMETER Inventory
        The inventory Get-SentinelGap builds from the raw files.

    .OUTPUTS
        $null when the rule passes; otherwise the finding New-Finding returns, with its
        Evidence and Detail.
    #>
    [CmdletBinding()] param([Parameter(Mandatory = $true)]$Inventory)
    if (-not $Inventory.TablesWithData) { return $null }
    $silent = @($Inventory.TablesWithData | Where-Object {
            $last7 = [double](Get-PropOrDefault $_ 'BillableLast7d' 0)
            $last90 = [double](Get-PropOrDefault $_ 'BillableLast90d' 0)
            ($last7 -eq 0) -and ($last90 -gt 0)
        })
    if ($silent.Count -gt 0) {
        $names = ($silent | Select-Object -ExpandProperty DataType) -join ', '
        $w = Get-GapWindow $Inventory
        return New-Finding -Evidence "$(Select-GapWording $silent.Count 'Silent table' 'Silent tables') (data in the last $(Format-GapDays $w.Days) but none in the last $(Format-GapDays $w.RecentDays)): $names." -Detail @{ Tables = $names }
    }
    return $null
}

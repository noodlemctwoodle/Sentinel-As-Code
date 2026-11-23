#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-LOG-08: High-volume table on Analytics with no transform

.DESCRIPTION
    Gap check for rule SAC-LOG-08 (Resources/Data/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Logging/Test-NoisyTableHasTransform.ps1
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
# SAC-LOG-08, High-volume table on Analytics with no transform
# ------------------------------------------------------------
function Test-NoisyTableHasTransform {
    <#
    .SYNOPSIS
        Gap check SAC-LOG-08: High-volume table on Analytics with no transform

    .PARAMETER Inventory
        The inventory Get-SentinelGap builds from the raw files.

    .OUTPUTS
        $null when the rule passes; otherwise the finding New-Finding returns, with its
        Evidence and Detail.
    #>
    [CmdletBinding()] param([Parameter(Mandatory = $true)]$Inventory)
    if (-not $Inventory.TablesWithData) { return $null }
    $threshold = 50.0
    $candidates = @($Inventory.TablesWithData | Where-Object {
            (ConvertTo-GapPer30Days ([double](Get-PropOrDefault $_ 'BillableLast30d' 0)) $Inventory) -ge $threshold
        })
    if (-not $candidates) { return $null }

    $tablesWithTransform = @{}
    foreach ($dcr in @($Inventory.Dcrs)) {
        $flows = Get-PropOrDefault $dcr 'properties.dataFlows' @()
        foreach ($flow in @($flows)) {
            $transform = Get-PropOrDefault $flow 'transformKql' ''
            $output = Get-PropOrDefault $flow 'outputStream' ''
            if ($transform -and $output) {
                $tablesWithTransform[$output] = $true
            }
        }
    }

    $missing = @($candidates | Where-Object {
            -not $tablesWithTransform.ContainsKey("Microsoft-Table-$($_.DataType)") -and
            -not $tablesWithTransform.ContainsKey("Custom-$($_.DataType)")
        })
    if ($missing.Count -gt 0) {
        $names = ($missing | Select-Object -ExpandProperty DataType) -join ', '
        return New-Finding -Evidence "$(Select-GapWording $missing.Count 'High-volume Analytics-plan table' 'High-volume Analytics-plan tables') with no DCR transform: $names." -Detail @{ Tables = $names }
    }
    return $null
}

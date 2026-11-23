#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-LOG-02: High-volume table candidate for Basic/Auxiliary

.DESCRIPTION
    Gap check for rule SAC-LOG-02 (Resources/Data/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Logging/Test-HighVolumeTablePlanCandidate.ps1
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
# SAC-LOG-02, High-volume table candidate for Basic/Auxiliary
# ------------------------------------------------------------
function Test-HighVolumeTablePlanCandidate {
    <#
    .SYNOPSIS
        Gap check SAC-LOG-02: High-volume table candidate for Basic/Auxiliary

    .PARAMETER Inventory
        The inventory Get-SentinelGap builds from the raw files.

    .OUTPUTS
        $null when the rule passes; otherwise the finding New-Finding returns, with its
        Evidence and Detail.
    #>
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    $analytics = @{}
    foreach ($t in @($Inventory.WorkspaceTables)) {
        $name = Get-PropOrDefault $t 'name' ''
        $plan = Get-PropOrDefault $t 'properties.plan' ''
        if ($name -and $plan -eq 'Analytics') { $analytics[$name] = $true }
    }
    $candidates = @($Inventory.TablesWithData | Where-Object {
        (ConvertTo-GapPer30Days ([double](Get-PropOrDefault $_ 'BillableLast30d' 0)) $Inventory) -gt 50.0 -and
        $analytics.ContainsKey((Get-PropOrDefault $_ 'DataType' ''))
    })
    if ($candidates.Count -gt 0) {
        $names = ($candidates | Select-Object -ExpandProperty DataType) -join ', '
        return New-Finding -Evidence "$(Select-GapWording $candidates.Count 'Analytics-plan table above 50 GB per 30 days that is a Basic/Auxiliary candidate' 'Analytics-plan tables above 50 GB per 30 days that are Basic/Auxiliary candidates'): $names." -Detail @{ Tables = $names }
    }
    return $null
}

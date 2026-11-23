#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-LOG-18: AzureDiagnostics carries multiple resource providers

.DESCRIPTION
    Gap check for rule SAC-LOG-18 (Resources/Data/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Logging/Test-AzureDiagnosticsResourceSpecific.ps1
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
# SAC-LOG-18, AzureDiagnostics carries multiple resource providers
# ------------------------------------------------------------
function Test-AzureDiagnosticsResourceSpecific {
    <#
    .SYNOPSIS
        Gap check SAC-LOG-18: AzureDiagnostics carries multiple resource providers

    .PARAMETER Inventory
        The inventory Get-SentinelGap builds from the raw files.

    .OUTPUTS
        $null when the rule passes; otherwise the finding New-Finding returns, with its
        Evidence and Detail.
    #>
    [CmdletBinding()] param([Parameter(Mandatory = $true)]$Inventory)
    $ad = @($Inventory.TablesWithData | Where-Object {
            (Get-PropOrDefault $_ 'DataType' '') -eq 'AzureDiagnostics'
        } | Select-Object -First 1)
    if ($ad.Count -eq 0) { return $null }
    $gb30 = Get-GapBillable30d $ad[0]
    if ((ConvertTo-GapPer30Day $gb30 $Inventory) -lt 10.0) { return $null }    # smaller threshold, even 10 GB per 30 days across many RPs is messy
    # We don't know per-RP breakdown from tables-with-data alone (the
    # AzureDiagnostics rendering is summarised in 14-coverage-breakdowns.md
    # but isn't a separate _raw capture). Flag based on volume alone, the
    # remediation is still correct: switch any RP that has a dedicated
    # resource-specific table.
    return New-Finding -Evidence "AzureDiagnostics ingested $(Format-BlueprintGb $gb30) GB in the last $(Format-GapDay (Get-GapWindow $Inventory).Days). Resource-specific tables are cheaper, faster to query, and have stable schemas, review diagnostic settings and switch each resource type to dedicated table mode." -Detail @{ Gb30d = $gb30 }
}

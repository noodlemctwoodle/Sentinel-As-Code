#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-LOG-06: Azure Firewall logs collected twice

.DESCRIPTION
    Gap check for rule SAC-LOG-06 (Resources/Data/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Logging/Test-AzureFirewallDuplicateLogging.ps1
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
# SAC-LOG-06, Azure Firewall logs collected twice
# ------------------------------------------------------------
function Test-AzureFirewallDuplicateLogging {
    <#
    .SYNOPSIS
        Gap check SAC-LOG-06: Azure Firewall logs collected twice

    .PARAMETER Inventory
        The inventory Get-SentinelGap builds from the raw files.

    .OUTPUTS
        $null when the rule passes; otherwise the finding New-Finding returns, with its
        Evidence and Detail.
    #>
    [CmdletBinding()] param([Parameter(Mandatory = $true)]$Inventory)
    if (@($Inventory.AzureDiagnosticsCategories).Count -eq 0) { return $null }
    if (-not $Inventory.TablesWithData) { return $null }
    $legacy = @($Inventory.AzureDiagnosticsCategories | Where-Object {
            $null -ne $_ -and ([string](Get-PropOrDefault $_ 'Category' '')) -match '^(AzureFirewall|AZFW)'
        })
    $structured = @($Inventory.TablesWithData | Where-Object {
            ([string](Get-PropOrDefault $_ 'DataType' '')) -match '^AZFW' -and (Get-GapIngested7d $_) -gt 0
        })
    if ($legacy.Count -eq 0 -or $structured.Count -eq 0) { return $null }
    $legacyRows = ($legacy | ForEach-Object { ConvertTo-GapInt (Get-PropOrDefault $_ 'LogCount' 0) } | Measure-Object -Sum).Sum
    $categories = @($legacy | ForEach-Object { [string](Get-PropOrDefault $_ 'Category' '') } | Sort-Object -Unique)
    $tables = @($structured | ForEach-Object { [string](Get-PropOrDefault $_ 'DataType' '') } | Sort-Object -Unique)
    $structuredGb = (($structured | ForEach-Object { Get-GapBillable30d $_ }) | Measure-Object -Sum).Sum
    return New-Finding -Evidence "Azure Firewall writes to both AzureDiagnostics ($($categories -join ', '); $(Format-BlueprintPlural $legacyRows 'row') in the last $(Format-GapDays (Get-GapWindow $Inventory).Days)) and the resource-specific tables ($($tables -join ', '); $(Format-BlueprintGb $structuredGb) GB in the same window). The same events are ingested and billed twice." -Detail @{
        LegacyCategories = $categories
        LegacyRows7d     = $legacyRows
        StructuredTables = $tables
        StructuredGb30d  = [math]::Round($structuredGb, 1)
    }
}

#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-PLT-02: CLv1 (HTTP Data Collector API) custom log tables still in use

.DESCRIPTION
    Gap check for rule SAC-PLT-02 (Resources/Data/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Platform/Test-CustomLogsV1Migration.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-16
    Component:    iSOC Blueprint, Gap Engine
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# ------------------------------------------------------------
# SAC-PLT-02, CLv1 (HTTP Data Collector API) custom log tables still in use
# ------------------------------------------------------------
function Test-CustomLogsV1Migration {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    if (-not $Inventory.WorkspaceTables -or -not $Inventory.TablesWithData -or -not $Inventory.Dcrs) { return $null }

    # Project the set of _CL tables that have any DCR feeding them. A DCR's
    # dataFlows[].outputStream is shaped "Custom-<TableName>_CL" when it
    # writes into a custom table; index by the bare table name.
    $tablesWithDcr = @{}
    foreach ($dcr in $Inventory.Dcrs) {
        $flows = Get-PropOrDefault $dcr 'properties.dataFlows' @()
        foreach ($f in @($flows)) {
            $stream = Get-PropOrDefault $f 'outputStream' ''
            if ($stream -match '^Custom-(.+)$') {
                $tablesWithDcr[$matches[1]] = $true
            }
        }
    }

    # Project _CL tables that have data in the lookback.
    $active = @{}
    foreach ($t in $Inventory.TablesWithData) {
        $name = Get-PropOrDefault $t 'DataType' ''
        $gb90 = [double](Get-PropOrDefault $t 'BillableLast90d' 0)
        if ($name -and $gb90 -gt 0) { $active[$name] = $true }
    }

    # Filter to genuine custom-log tables. tableType alone is unreliable, 
    # some workspaces report AzureDiagnostics and other Microsoft service
    # tables as 'CustomLog' when custom diagnostic settings have been
    # written to them. The `_CL` name suffix is enforced at table creation
    # and is the authoritative custom-table marker.
    $clv1 = @($Inventory.WorkspaceTables | Where-Object {
        $name = Get-PropOrDefault $_ 'name' ''
        $type = Get-PropOrDefault $_ 'properties.schema.tableType' ''
        ($type -eq 'CustomLog') -and ($name -like '*_CL') -and $active.ContainsKey($name) -and (-not $tablesWithDcr.ContainsKey($name))
    })
    if ($clv1.Count -eq 0) { return $null }
    $names = ($clv1 | ForEach-Object { Get-EvidenceName $_ 'name' 'Unnamed table' }) -join ', '
    return New-Finding -Evidence "$(Format-BlueprintPlural $clv1.Count 'custom log table') $(Select-GapWording $clv1.Count 'receives' 'receive') data but no DCR feeds $(Select-GapWording $clv1.Count 'it' 'them'), likely still using the HTTP Data Collector API (CLv1). Affected: $names. The API $(if ([datetime]::UtcNow -ge [datetime]::new(2026, 9, 14, 0, 0, 0, [System.DateTimeKind]::Utc)) { 'retired on 14 Sep 2026' } else { 'retires on 14 Sep 2026' })." -Detail @{ Count = $clv1.Count }
}

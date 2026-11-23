#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-PLT-10: Connector connected but its tables received no data

.DESCRIPTION
    Gap check for rule SAC-PLT-10 (Resources/Data/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Platform/Test-ConnectorTableMismatch.ps1
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
# SAC-PLT-10, Connector connected but its tables received no data
# ------------------------------------------------------------
function Test-ConnectorTableMismatch {
    <#
    .SYNOPSIS
        Gap check SAC-PLT-10: Connector connected but its tables received no data

    .PARAMETER Inventory
        The inventory Get-SentinelGap builds from the raw files.

    .OUTPUTS
        $null when the rule passes; otherwise the finding New-Finding returns, with its
        Evidence and Detail.
    #>
    [CmdletBinding()] param([Parameter(Mandatory = $true)]$Inventory)
    if (-not $Inventory.DataConnectors -or -not $Inventory.TablesWithData) { return $null }
    # Volume per table over the recent window, free tables (OfficeActivity,
    # SecurityAlert) included: billable volume alone made them look silent.
    $activity = Get-TableActivity -TablesWithData @($Inventory.TablesWithData)
    $hasData = { param($t) $activity.ContainsKey($t) -and $activity[$t] -gt 0 }

    # The core tables these connectors must fill, checked one by one.
    $kindToTables = @{
        'AzureActiveDirectory'                      = @('SigninLogs', 'AuditLogs', 'AADNonInteractiveUserSignInLogs')
        'Office365'                                 = @('OfficeActivity')
        'AzureSecurityCenter'                       = @('SecurityAlert')
        'MicrosoftDefenderAdvancedThreatProtection' = @('SecurityAlert')
        'MicrosoftThreatProtection'                 = @('SecurityIncident', 'SecurityAlert')
    }
    $bad = [System.Collections.Generic.List[string]]::new()
    $silent = [System.Collections.Generic.List[object]]::new()
    foreach ($c in @($Inventory.DataConnectors)) {
        if ($null -eq $c) { continue }
        $kind = [string](Get-PropOrDefault $c 'kind' '')
        if (-not $kindToTables.ContainsKey($kind)) { continue }
        foreach ($expected in $kindToTables[$kind]) {
            if (-not (& $hasData $expected)) { $bad.Add("$kind to $expected") }
        }
    }
    # Every other connected connector the catalogue knows: silent when none
    # of the tables it lists received data. A catalogue list can include
    # tables the connector does not write, so one quiet table proves nothing.
    $catalogue = Get-PropOrDefault $Inventory 'ConnectorCatalogue' $null
    if ($catalogue) {
        $others = @($Inventory.DataConnectors | Where-Object { $null -ne $_ -and -not $kindToTables.ContainsKey([string](Get-PropOrDefault $_ 'kind' '')) })
        foreach ($row in @(Get-ConnectorCatalogueStatus -Catalogue $catalogue -Connectors $others -Activity $activity)) {
            if ($row.Status -eq 'Silent') { $silent.Add($row) }
        }
    }
    if ($bad.Count -eq 0 -and $silent.Count -eq 0) { return $null }
    $parts = @()
    # A table can be expected by several connectors, so count the tables.
    $badTables = @($bad | ForEach-Object { ($_ -split ' to ')[-1] } | Sort-Object -Unique).Count
    if ($bad.Count) {
        $parts += "$(Format-BlueprintPlural $badTables 'core table') with no data in the last $(Format-GapDay (Get-GapWindow $Inventory).RecentDays): $($bad -join '; ')"
    }
    if ($silent.Count) {
        $parts += "$(Format-BlueprintPlural $silent.Count 'connector') with no data in any table $(Select-GapWording $silent.Count 'it writes' `
            'they write'): " +
        (@($silent | ForEach-Object { "$($_.Connector) ($($_.Tables -join ', '))" }) -join '; ')
    }
    return New-Finding -Evidence "Connected data connectors that are not delivering, $($parts -join '; and ')." -Detail @{
        Mismatches       = @($bad)
        SilentConnectors = @($silent | ForEach-Object { [pscustomobject]@{ Connector = $_.Connector; Id = $_.Id; Tables = $_.Tables } })
    }
}

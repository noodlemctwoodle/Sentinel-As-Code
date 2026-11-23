#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-INV-04: Orphan tables (schema, no data in the lookback)

.DESCRIPTION
    Gap check for rule SAC-INV-04 (Resources/Data/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Inventory/Test-OrphanTables.ps1
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
# SAC-INV-04, Orphan tables (schema, no data in the lookback)
# ------------------------------------------------------------
function Test-OrphanTables {
    <#
    .SYNOPSIS
        Gap check SAC-INV-04: Orphan tables (schema, no data in the lookback)

    .PARAMETER Inventory
        The inventory Get-SentinelGap builds from the raw files.

    .OUTPUTS
        $null when the rule passes; otherwise the finding New-Finding returns, with its
        Evidence and Detail.
    #>
    [CmdletBinding()] param([Parameter(Mandatory = $true)]$Inventory)
    if (-not $Inventory.WorkspaceTables -or -not $Inventory.TablesWithData) { return $null }
    $populated = @{}
    foreach ($t in $Inventory.TablesWithData) {
        $populated[(Get-PropOrDefault $t 'DataType' '')] = $true
    }
    $orphans = @($Inventory.WorkspaceTables | Where-Object {
            $name = Get-PropOrDefault $_ 'name' ''
            $type = Get-PropOrDefault $_ 'properties.schema.tableType' ''
            # Custom (_CL) tables only. Microsoft pre-defined tables without data
            # are part of every workspace's catalogue (~750 of them on a typical
            # Sentinel workspace) and aren't orphans, they're 'sources we
            # haven't onboarded'. Custom tables, on the other hand, were
            # explicitly created to receive data; if none has arrived in the lookback,
            # the source is broken or the table should be deleted.
            $type -eq 'CustomLog' -and -not $populated.ContainsKey($name)
        })
    if ($orphans.Count -gt 0) {
        return New-Finding -Evidence "$(Format-BlueprintPlural $orphans.Count 'table') $(Select-GapWording $orphans.Count 'has' 'have') a schema but no data in the last $(Format-GapDays (Get-GapWindow $Inventory).Days)." -Detail @{ Count = $orphans.Count }
    }
    return $null
}

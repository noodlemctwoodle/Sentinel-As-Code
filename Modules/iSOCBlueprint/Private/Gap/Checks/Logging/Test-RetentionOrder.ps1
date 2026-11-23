#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-LOG-20: Analytics retention longer than total retention

.DESCRIPTION
    Gap check for rule SAC-LOG-20 (Resources/Data/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Logging/Test-RetentionOrder.ps1
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
# SAC-LOG-20, Analytics retention longer than total retention
# ------------------------------------------------------------
function Test-RetentionOrder {
    <#
    .SYNOPSIS
        Gap check SAC-LOG-20: Analytics retention longer than total retention

    .PARAMETER Inventory
        The inventory Get-SentinelGap builds from the raw files.

    .OUTPUTS
        $null when the rule passes; otherwise the finding New-Finding returns, with its
        Evidence and Detail.
    #>
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    if ($Inventory.RawFiles -notcontains 'workspace-tables.json') { return $null }
    $bad = @($Inventory.WorkspaceTables | Where-Object { $null -ne $_ } | ForEach-Object {
        $analytics = ConvertTo-GapInt (Get-PropOrDefault $_ 'properties.retentionInDays' 0)
        $total = ConvertTo-GapInt (Get-PropOrDefault $_ 'properties.totalRetentionInDays' 0)
        if ($analytics -gt 0 -and $total -gt 0 -and $analytics -gt $total) {
            [pscustomobject]@{ Table = [string](Get-PropOrDefault $_ 'name' ''); AnalyticsDays = $analytics; TotalDays = $total }
        }
    } | Sort-Object Table)
    if ($bad.Count -eq 0) { return $null }
    $names = @($bad | ForEach-Object { "$($_.Table) (analytics $(Format-BlueprintPlural $_.AnalyticsDays 'day'), total $(Format-BlueprintPlural $_.TotalDays 'day'))" })
    return New-Finding -Evidence "$(Format-BlueprintPlural $bad.Count 'table') $(Select-GapWording $bad.Count 'has' 'have') analytics retention longer than total retention: $($names -join ', ')." -Detail @{ Tables = $bad }
}

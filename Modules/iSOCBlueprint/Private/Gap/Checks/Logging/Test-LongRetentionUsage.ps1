#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-LOG-21: Long-term retention with no usage evidence

.DESCRIPTION
    Gap check for rule SAC-LOG-21 (Resources/Data/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Logging/Test-LongRetentionUsage.ps1
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
# SAC-LOG-21, Long-term retention with no usage evidence
# ------------------------------------------------------------
function Test-LongRetentionUsage {
    <#
    .SYNOPSIS
        Gap check SAC-LOG-21: Long-term retention with no usage evidence

    .PARAMETER Inventory
        The inventory Get-SentinelGap builds from the raw files.

    .OUTPUTS
        $null when the rule passes; otherwise the finding New-Finding returns, with its
        Evidence and Detail.
    #>
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    # Audited queries are one of the four signals; without them every table
    # would look unused, so the check needs that capture and the rule map.
    if ($Inventory.RawFiles -notcontains 'table-query-usage.json' -or $Inventory.RawFiles -notcontains 'rule-table-references.json') { return $null }
    $long = @($Inventory.WorkspaceTables | Where-Object { $null -ne $_ } | Where-Object {
        $analytics = ConvertTo-GapInt (Get-PropOrDefault $_ 'properties.retentionInDays' 0)
        $total = ConvertTo-GapInt (Get-PropOrDefault $_ 'properties.totalRetentionInDays' 0)
        ([string](Get-PropOrDefault $_ 'properties.plan' '')) -eq 'DataLake' -or $total -gt $analytics
    })
    if ($long.Count -eq 0) { return $null }
    $readByRule = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($ref in @($Inventory.RuleTableReferences)) {
        if ($null -eq $ref -or -not (ConvertTo-GapBool (Get-PropOrDefault $ref 'Enabled' $false))) { continue }
        foreach ($t in @(Get-PropOrDefault $ref 'Tables' @())) { if ($t) { [void]$readByRule.Add([string]$t) } }
    }
    $summaryQueries = @($Inventory.SummaryRules | Where-Object { $null -ne $_ } | ForEach-Object {
        [string](Get-PropOrDefault $_ 'properties.ruleDefinition.query' (Get-PropOrDefault $_ 'properties.query' ''))
    })
    $derived = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($t in @($Inventory.WorkspaceTables)) {
        $n = [string](Get-PropOrDefault $t 'name' '')
        if ($n -match '^(.+?)_(SRCH|RST|KQL_CL)$') { [void]$derived.Add($Matches[1]) }
    }
    $queried = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($row in @($Inventory.TableQueryUsage)) {
        if ($null -ne $row -and (ConvertTo-GapInt (Get-PropOrDefault $row 'Queries' 0)) -gt 0) { [void]$queried.Add([string](Get-PropOrDefault $row 'Table' '')) }
    }
    $unused = @($long | Where-Object {
        $n = [string](Get-PropOrDefault $_ 'name' '')
        $inSummary = [bool]($summaryQueries | Where-Object { $_ -match ('\b' + [regex]::Escape($n) + '\b') } | Select-Object -First 1)
        -not ($readByRule.Contains($n) -or $inSummary -or $derived.Contains($n) -or $queried.Contains($n))
    } | ForEach-Object {
        [pscustomobject]@{ Table = [string]$_.name; TotalDays = ConvertTo-GapInt (Get-PropOrDefault $_ 'properties.totalRetentionInDays' 0); Plan = [string](Get-PropOrDefault $_ 'properties.plan' '') }
    } | Sort-Object Table)
    if ($unused.Count -eq 0) { return $null }
    $names = @($unused | ForEach-Object { "$($_.Table) ($(Format-BlueprintPlural $_.TotalDays 'day') total)" })
    return New-Finding -Evidence "$(Format-BlueprintPlural $unused.Count 'table') $(Select-GapWording $unused.Count 'keeps' 'keep') data beyond $(Select-GapWording $unused.Count 'its' 'their') analytics retention with no enabled rule, summary rule, search or restore job, or audited query reading $(Select-GapWording $unused.Count 'it' 'them'): $($names -join ', ')." -Detail @{ Tables = $unused }
}

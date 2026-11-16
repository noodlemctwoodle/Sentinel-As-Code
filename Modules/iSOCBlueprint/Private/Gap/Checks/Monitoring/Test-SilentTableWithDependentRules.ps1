#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-MON-06: Table that enabled rules depend on has gone silent

.DESCRIPTION
    Gap check for rule SAC-MON-06 (Resources/Data/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Monitoring/Test-SilentTableWithDependentRules.ps1
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
# SAC-MON-06, Table that enabled rules depend on has gone silent
# ------------------------------------------------------------
function Test-SilentTableWithDependentRules {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    if (@($Inventory.RuleTableReferences).Count -eq 0) { return $null }
    if (-not $Inventory.TablesWithData) { return $null }
    # The extractor returns every bare identifier a query reads, which
    # includes functions and parsers. Intersecting with the workspace's
    # table list keeps only real tables; with no table list there is no
    # safe way to do that, so stay quiet.
    $known = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($t in @($Inventory.WorkspaceTables)) {
        $n = [string](Get-PropOrDefault $t 'name' '')
        if ($n) { [void]$known.Add($n) }
    }
    if ($known.Count -eq 0) { return $null }

    $ingested = @{}
    foreach ($row in $Inventory.TablesWithData) {
        $n = [string](Get-PropOrDefault $row 'DataType' '')
        if ($n) { $ingested[$n] = Get-GapIngested7d $row }
    }
    $rulesByTable = @{}
    foreach ($ref in @($Inventory.RuleTableReferences)) {
        if ($null -eq $ref -or -not (ConvertTo-GapBool (Get-PropOrDefault $ref 'Enabled' $false))) { continue }
        $ruleName = Get-EvidenceName $ref 'RuleName', 'RuleId' 'Unnamed rule'
        foreach ($t in @(Get-PropOrDefault $ref 'Tables' @())) {
            if (-not $t -or -not $known.Contains([string]$t)) { continue }
            if (-not $rulesByTable.ContainsKey($t)) { $rulesByTable[$t] = [System.Collections.Generic.List[string]]::new() }
            $rulesByTable[$t].Add($ruleName)
        }
    }
    $silent = @($rulesByTable.Keys | Where-Object { -not $ingested.ContainsKey($_) -or $ingested[$_] -le 0 } | Sort-Object)
    if ($silent.Count -eq 0) { return $null }
    $sample = ($silent | ForEach-Object {
        "$_ ($(Format-BlueprintPlural ($rulesByTable[$_].Count) 'rule'): $(@($rulesByTable[$_]) -join ', '))"
    }) -join '; '
    $dependent = @($silent | ForEach-Object { $rulesByTable[$_] } | Sort-Object -Unique).Count
    return New-Finding -Evidence "$(Format-BlueprintPlural $silent.Count 'table') that enabled analytics rules read $(Select-GapWording $silent.Count 'has' 'have') ingested nothing in the last $(Format-GapDays (Get-GapWindow $Inventory).RecentDays): $sample. $(Select-GapWording $dependent 'That rule cannot' 'Those rules cannot') fire." -Detail @{
        Count  = $silent.Count
        Tables = @($silent | ForEach-Object { [pscustomobject]@{ Table = $_; Rules = @($rulesByTable[$_]) } })
    }
}

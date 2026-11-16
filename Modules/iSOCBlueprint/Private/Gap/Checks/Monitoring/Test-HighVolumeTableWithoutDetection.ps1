#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-MON-05: High-volume table with no enabled rule referencing it

.DESCRIPTION
    Gap check for rule SAC-MON-05 (Resources/Data/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Monitoring/Test-HighVolumeTableWithoutDetection.ps1
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
# SAC-MON-05, High-volume table with no enabled rule referencing it
# ------------------------------------------------------------
function Test-HighVolumeTableWithoutDetection {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    # Without the reference file there is no way to tell "no rule reads
    # this" from "the mapping was not computed", so stay quiet.
    if ($Inventory.RawFiles -notcontains 'rule-table-references.json') { return $null }
    if (-not $Inventory.TablesWithData) { return $null }
    $threshold = 5.0
    $referenced = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($ref in @($Inventory.RuleTableReferences)) {
        if ($null -eq $ref -or -not (ConvertTo-GapBool (Get-PropOrDefault $ref 'Enabled' $false))) { continue }
        foreach ($t in @(Get-PropOrDefault $ref 'Tables' @())) { if ($t) { [void]$referenced.Add([string]$t) } }
    }
    # Defender XDR custom detections read the same data; an enabled one
    # counts as coverage for the tables it queries.
    foreach ($ref in @(Get-PropOrDefault $Inventory 'CustomDetectionRefs' @())) {
        if ($null -eq $ref -or -not (ConvertTo-GapBool (Get-PropOrDefault $ref 'Enabled' $false))) { continue }
        foreach ($t in @(Get-PropOrDefault $ref 'Tables' @())) { if ($t) { [void]$referenced.Add([string]$t) } }
    }
    # Sentinel's own operational tables are outputs, not detection sources.
    $operational = @('SecurityIncident', 'SecurityAlert', 'Usage', 'Operation', 'LAQueryLogs', 'SentinelHealth', 'SentinelAudit', 'AzureMetrics')
    $uncovered = @($Inventory.TablesWithData | Where-Object {
        $t = [string](Get-PropOrDefault $_ 'DataType' '')
        $t -and ($operational -notcontains $t) -and (-not $referenced.Contains($t)) -and
            ((ConvertTo-GapPer30Days (Get-GapBillable30d $_) $Inventory) -ge $threshold)
    } | Sort-Object { -(Get-GapBillable30d $_) })
    if ($uncovered.Count -eq 0) { return $null }

    # The figure the dashboard shows for data no detection reads: every table
    # with data, the small and the operational ones included, totalled and
    # taken off the covered total as the dashboard does.
    $estateGb = 0.0; $coveredGb = 0.0
    foreach ($row in @($Inventory.TablesWithData)) {
        if ($null -eq $row) { continue }
        $t = [string](Get-PropOrDefault $row 'DataType' '')
        $gb = Get-GapBillable30d $row
        if (-not $t -or $gb -le 0) { continue }
        $estateGb += $gb
        if ($referenced.Contains($t)) { $coveredGb += $gb }
    }
    $allTablesGb = $estateGb - $coveredGb

    # Suggest templates that read the table and are neither deployed already
    # nor deprecated, nor shipped only by a deprecated Content Hub solution,
    # highest severity first.
    $severityRank = @{ High = 0; Medium = 1; Low = 2; Informational = 3 }
    $solutionMap = if (Get-Command Get-TemplateSolutionMap -ErrorAction SilentlyContinue) {
        Get-TemplateSolutionMap -Installed @(
            Get-PropOrDefault $Inventory 'ContentPackages' @() | Where-Object { $null -ne $_ }
        ) -Catalogue @(Get-PropOrDefault $Inventory 'ContentProductPackages' @() | Where-Object { $null -ne $_ })
    } else { $null }
    $templates = @($Inventory.TemplateTableReferences | Where-Object {
        $null -ne $_ -and -not (ConvertTo-GapBool (Get-PropOrDefault $_ 'Deprecated' $false)) -and
            -not (ConvertTo-GapBool (Get-PropOrDefault $_ 'AlreadyDeployed' $false)) -and
        -not ($solutionMap -and (Test-TemplateRetired -Map $solutionMap -TemplateId ([string](Get-PropOrDefault $_ 'TemplateId' ''))))
    })
    $rows = @(foreach ($table in $uncovered) {
        $name = [string](Get-PropOrDefault $table 'DataType' '')
        $candidates = @($templates | Where-Object { @(Get-PropOrDefault $_ 'Tables' @()) -contains $name } | Sort-Object {
            $sev = [string](Get-PropOrDefault $_ 'Severity' '')
            if ($severityRank.ContainsKey($sev)) { $severityRank[$sev] } else { 9 }
        }, { [string](Get-PropOrDefault $_ 'DisplayName' '') })
        [pscustomobject]@{
            Table              = $name
            Gb30d              = [math]::Round((Get-GapBillable30d $table), 2)
            SuggestedTemplates = @($candidates | ForEach-Object { [string](Get-PropOrDefault $_ 'DisplayName' '') })
        }
    })
    # Summed unrounded and rounded once, so the total is the tables' true sum.
    $totalGb = (($uncovered | ForEach-Object { Get-GapBillable30d $_ }) | Measure-Object -Sum).Sum
    $sample = ($rows | ForEach-Object {
        $hint = if ($_.SuggestedTemplates.Count -gt 0) { " (templates: $($_.SuggestedTemplates -join ', '))" } else { '' }
        "$($_.Table) $(Format-BlueprintGb $_.Gb30d) GB$hint"
    }) -join '; '
    # Say what the finding covers, and the dashboard's larger figure when
    # there is one, so the two numbers reconcile.
    $ofAll = ''
    if ([math]::Round($allTablesGb, 2) -ne [math]::Round($totalGb, 2)) {
        $ofAll = ", of $(Format-BlueprintGb $allTablesGb) GB in every table no detection reads (the rest is in smaller tables or Sentinel's own operational tables)"
    }
    return New-Finding -Evidence "$(Format-BlueprintPlural $rows.Count 'table') of $(Format-BlueprintCount $threshold) GB a month or more $(Select-GapWording `
            $rows.Count 'ingests' 'ingest') $(Format-BlueprintGb $totalGb) GB in the last $(Format-GapDays (Get-GapWindow $Inventory).Days) with no enabled Sentinel rule or Defender custom detection reading $(Select-GapWording $rows.Count 'it' 'them')$($ofAll): $sample." -Detail @{
        Count = $rows.Count
        TotalGb30d = [math]::Round($totalGb, 2)
        AllTablesGb30d = [math]::Round($allTablesGb, 2)
        Tables = $rows
    }
}

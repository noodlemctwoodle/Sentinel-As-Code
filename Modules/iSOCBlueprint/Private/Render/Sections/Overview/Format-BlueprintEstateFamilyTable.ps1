#Requires -Version 7.6

<#
.SYNOPSIS
    Render the estate model as a table of source families.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/Overview/Format-BlueprintEstateFamilyTable.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.2
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Format-BlueprintEstateFamilyTable {
    <#
    .SYNOPSIS
        Render the estate model as a table of source families.

    .DESCRIPTION
        One row per source family: tables, GB, how many of those tables a detection
        reads, and the first-party alerts raised beside the family. A family that
        has first-party alerts but no table of its own still gets a row. The table
        is followed by a line giving the Defender XDR custom detections, or saying
        they were not captured.

    .PARAMETER Estate
        The estate model from New-BlueprintEstateModel.

    .OUTPUTS
        [string] of Markdown.
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param($Estate)
    $alertsByFamily = @{}
    foreach ($p in @($Estate.ProductAlerts)) {
        $fam = [string]$p.Family
        if (-not $alertsByFamily.ContainsKey($fam)) { $alertsByFamily[$fam] = New-Object System.Collections.Generic.List[string] }
        $alertsByFamily[$fam].Add("$($p.Product) $(Format-BlueprintCount $p.Alerts)")
    }
    $rows = @($Estate.Sources | ForEach-Object {
            $fam = [string]$_.Category
            [pscustomobject]@{
                Family           = $fam
                Tables           = $_.Tables
                Gb30d            = Format-BlueprintGb $_.Gb
                TablesRead       = $_.Covered
                GbRead           = Format-BlueprintGb $_.CoveredGb
                FirstPartyAlerts = $(if ($alertsByFamily.ContainsKey($fam)) { $alertsByFamily[$fam] -join '; ' } else { '' })
            }
        })
    foreach ($fam in @($alertsByFamily.Keys | Sort-Object)) {
        if (-not @($rows | Where-Object { $_.Family -eq $fam }).Count) {
            $rows += [pscustomobject]@{
                Family           = $fam
                Tables           = 0
                Gb30d            = Format-BlueprintGb 0
                TablesRead       = 0
                GbRead           = Format-BlueprintGb 0
                FirstPartyAlerts = ($alertsByFamily[$fam] -join '; ')
            }
        }
    }
    $customLine = if ($Estate.CustomDetectionsCaptured) {
        "**Defender XDR custom detections:** $(Format-BlueprintCount $Estate.CustomDetectionsEnabled) enabled of $(Format-BlueprintCount $Estate.CustomDetectionsTotal) defined; the tables they read count as covered above."
    } else {
        '**Defender XDR custom detections:** not captured in this run (the identity needs the Microsoft Graph permission CustomDetection.Read.All), so coverage counts Sentinel rules only.'
    }
    @"
### Source families

Each family's share of the last {lookback} of billable data, how many of its tables an enabled Sentinel rule or Defender custom detection reads, and the first-party alerts (Defender XDR, Entra ID Protection, Defender for Identity, Defender for Cloud) raised beside it in the same window. First-party detections run inside their product and read no workspace table, so they never move a table into the covered column.

$(Format-BlueprintTable -Items $rows -Columns 'Family','Tables','Gb30d','TablesRead','GbRead','FirstPartyAlerts')

$customLine
"@
}

#Requires -Version 7.6

<#
.SYNOPSIS
    Render the estate model as sankey rows.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/Overview/Format-BlueprintEstateSankey.ps1
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

function Format-BlueprintEstateSankey {
    <#
    .SYNOPSIS
        Render the estate model as sankey rows.

    .DESCRIPTION
        sankey-beta reads CSV rows: source, target, value. Labels are quoted so a
        family name with a comma cannot split a row; values are GB. The block also
        carries the estate as data for the SharePoint graphic (every family's GB and
        the part a detection reads, and the four stages as in use of a whole).
        Returns _Nothing to draw._ when there are no rows.

    .PARAMETER Estate
        The estate model from New-BlueprintEstateModel.

    .OUTPUTS
        [string]: a fenced mermaid block.
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param($Estate)
    function _Gb([double]$v) {
        if ($v -le 0) { return $null }
        return ([math]::Max(0.01, [math]::Round($v, 2))).ToString('0.##', [System.Globalization.CultureInfo]::InvariantCulture)
    }
    $rows = New-Object System.Collections.Generic.List[string]
    foreach ($src in $Estate.Sources) {
        $c = _Gb $src.CoveredGb
        $u = _Gb ($src.Gb - $src.CoveredGb)
        if ($c) { $rows.Add("`"$($src.Category)`",`"Ingestion`",$c") }
        if ($u) { $rows.Add("`"$($src.Category)`",`"Not monitored`",$u") }
    }
    $covered = _Gb $Estate.CoveredGb
    if ($covered) {
        $det = "Detection ($(Format-BlueprintPlural $Estate.RulesEnabled 'enabled rule'))"
        $al = "Alerts ($(Format-BlueprintCount $Estate.Alerts) in {lookback-d})"
        $inc = "Incidents ($(Format-BlueprintCount $Estate.Incidents) in {lookback-d})"
        $rows.Add("`"Ingestion`",`"$det`",$covered")
        $rows.Add("`"$det`",`"$al`",$covered")
        $rows.Add("`"$al`",`"$inc`",$covered")
        if ($Estate.Incidents -gt 0) {
            $closedShare = [double]$Estate.CoveredGb * $Estate.IncidentsClosed / $Estate.Incidents
            $c2 = _Gb $closedShare
            $o2 = _Gb ($Estate.CoveredGb - $closedShare)
            if ($c2) { $rows.Add("`"$inc`",`"Closed ($(Format-BlueprintCount $Estate.IncidentsClosed))`",$c2") }
            if ($o2) { $rows.Add("`"$inc`",`"Open ($(Format-BlueprintCount $Estate.IncidentsOpen))`",$o2") }
        }
    }
    if ($rows.Count -eq 0) { return '_Nothing to draw._' }
    $height = [math]::Max(360, 40 * $Estate.Sources.Count + 200)
    # The estate as data for the SharePoint graphic: every family's GB and
    # the part a detection reads, and the four stages as in use of a whole.
    # Counts with thousands separators, whatever the machine's culture.
    $n0 = { param($v) ([long]$v).ToString('N0', [System.Globalization.CultureInfo]::InvariantCulture) }
    $visual = Format-VisualLine -Kind 'estate' -Data ([ordered]@{
            windowDays = (Get-BlueprintWindow).Days
            totalGb    = [math]::Round([double]$Estate.TotalGb, 2)
            coveredGb  = [math]::Round([double]$Estate.CoveredGb, 2)
            sources    = @(
                $Estate.Sources |
                    Sort-Object { - [double]$_.Gb } |
                    ForEach-Object {
                        [ordered]@{
                            name      = [string]$_.Category
                            gb        = [math]::Round([double]$_.Gb, 2)
                            coveredGb = [math]::Round([double]$_.CoveredGb, 2)
                            tables    = [int]$_.Tables
                            covered   = [int]$_.Covered
                        }
                    }
            )
            stages     = @(
                [ordered]@{
                    name   = 'Ingestion'
                    value  = [int]$Estate.TablesActive
                    of     = [int]$Estate.TablesSeen
                    label  = 'tables with data in {lookback} still receiving data in the last {recent}'
                    detail = "$(Format-BlueprintGb $Estate.TotalGb) GB in {lookback}"
                }
                [ordered]@{
                    name   = 'Detection'
                    value  = [int]$Estate.TablesCovered
                    of     = [int]$Estate.TablesActive
                    label  = 'active tables read by an enabled detection'
                    detail = "$(& $n0 $Estate.RulesEnabled) enabled rules"
                }
                [ordered]@{
                    name   = 'Alerts'
                    value  = [int]$Estate.RulesFired
                    of     = [int]$Estate.RulesQueryEnabled
                    label  = 'scheduled and NRT rules that fired'
                    detail = "$(& $n0 $Estate.RuleAlerts) Sentinel alerts$(if ([long]$Estate.XdrAlerts -gt 0) { " and $(& $n0 $Estate.XdrAlerts) Defender XDR alerts" }) in {lookback}"
                }
                [ordered]@{
                    name   = 'Incidents'
                    value  = [int]$Estate.IncidentsClosed
                    of     = [int]$Estate.Incidents
                    label  = 'incidents closed'
                    detail = "$(& $n0 $Estate.IncidentsOpen) still open"
                }
            )
        })
    @"
``````mermaid
---
config:
  sankey:
    showValues: true
    width: 1200
    height: $height
---
sankey-beta
$visual

$($rows -join [Environment]::NewLine)
``````
"@
}

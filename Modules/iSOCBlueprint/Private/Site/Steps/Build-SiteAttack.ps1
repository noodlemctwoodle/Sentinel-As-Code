#Requires -Version 7.6

<#
.SYNOPSIS
    Build the ATT&CK coverage model and the incident classifications.

.DESCRIPTION
    A step of the SharePoint site build. Steps run in order and pass their results
    to later ones through the build context.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Site/Steps/Build-SiteAttack.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, SharePoint site build
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Build-SiteAttack {
    <#
    .SYNOPSIS
        Build the ATT&CK coverage model and the incident classifications.

    .PARAMETER Context
        The build context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the build context.
    $alertRaw = $Context.alertRaw
    $bag = $Context.bag
    $incSummaryRow = $Context.incSummaryRow
    $engineRoot = $Context.engineRoot

    # The Insights tab's ATT&CK grid: every rule (enabled or not) with where it
    # lands in the matrix, from the same Get-AttackCoverage the MITRE page uses.
    # Tactics in kill-chain order; every base technique with its sub-technique
    # ids, and every sub-technique's name, so the grid can show the gaps at both
    # levels; cells as rule indices.
    $attackModel = $null
    $attackCatalogue = Get-Content -LiteralPath (Join-Path $engineRoot 'Private/Resources/mitre-attack.json') -Raw | ConvertFrom-Json
    $attackRules = @($alertRaw | Where-Object { $_ })
    if ($attackCatalogue) {
        $cov = Get-AttackCoverage -Rules $attackRules -Catalogue $attackCatalogue
        $tacticById = @{}; foreach ($t in @($attackCatalogue.tactics)) { $tacticById[[string]$t.id] = $t }
        $killChain = 'TA0043', 'TA0042', 'TA0001', 'TA0002', 'TA0003', 'TA0004', 'TA0005', 'TA0006', 'TA0007', 'TA0008', 'TA0009', 'TA0011', 'TA0010', 'TA0040'
        $subName = @{}
        $subsByParent = @{}
        foreach ($t in @($attackCatalogue.techniques)) {
            if ($t.PSObject.Properties.Name -contains 'parentId' -and $t.parentId) {
                $subName[[string]$t.id] = [string]$t.name
                if (-not $subsByParent.ContainsKey([string]$t.parentId)) { $subsByParent[[string]$t.parentId] = [System.Collections.Generic.List[string]]::new() }
                $subsByParent[[string]$t.parentId].Add([string]$t.id)
            }
        }
        # Every sub-technique ATT&CK defines, plus any a rule maps that the
        # catalogue does not know (named by its id).
        $usedSubs = [ordered]@{}
        foreach ($s in ($subName.Keys | Sort-Object)) { $usedSubs[$s] = $subName[$s] }
        $cellList = foreach ($tac in ($cov.Cells.Keys | Sort-Object)) {
            foreach ($tech in ($cov.Cells[$tac].Keys | Sort-Object)) {
                $cell = $cov.Cells[$tac][$tech]
                [ordered]@{
                    tactic    = [string]$tac
                    technique = [string]$tech
                    rules     = @($cell.Rules | Sort-Object)
                    subs      = @(foreach ($s in ($cell.Subs.Keys | Sort-Object)) {
                            if (-not $usedSubs.Contains($s)) { $usedSubs[$s] = $(if ($subName.ContainsKey($s)) { $subName[$s] } else { $s }) }
                            [ordered]@{ id = [string]$s; rules = @($cell.Subs[$s] | Sort-Object) }
                        })
                }
            }
        }
        $attackModel = [ordered]@{
            tactics    = @(foreach ($id in $killChain) { if ($tacticById.ContainsKey($id)) { [ordered]@{ id = $id; name = [string]$tacticById[$id].name; short = [string]$tacticById[$id].sentinelShortName } } })
            techniques = @(foreach ($t in (@($attackCatalogue.techniques) | Where-Object { -not ($_.PSObject.Properties.Name -contains 'parentId' -and $_.parentId) } | Sort-Object id)) {
                    [ordered]@{ id = [string]$t.id; name = [string]$t.name; tactics = @($t.tacticsSentinel | Where-Object { $_ }); subTotal = [int]$cov.SubTotals[[string]$t.id]; subs = @($subsByParent[[string]$t.id] | Sort-Object) }
                })
            subNames   = $usedSubs
            rules      = @(foreach ($r in $cov.Rules) { [ordered]@{ name = $r.Name; enabled = $r.Enabled; kind = $r.Kind; severity = $r.Severity } })
            cells      = @($cellList)
        }
    }

    $incidentsByClassification = @()
    if ($incSummaryRow -and $incSummaryRow.PSObject.Properties['ByClassification']) {
        $bag = Get-BuildBag $incSummaryRow.ByClassification
        foreach ($k in ($bag.Keys | Sort-Object { $bag[$_] } -Descending)) { if ($bag[$k] -gt 0) { $incidentsByClassification += [ordered]@{ label = [string]$k; value = [long]$bag[$k] } } }
    }

    # Left in the build context for later steps.
    $Context.attackModel = $attackModel
    $Context.id = $id
    $Context.incidentsByClassification = $incidentsByClassification
    $Context.k = $k
    $Context.r = $r
}

#Requires -Version 7.6

<#
.SYNOPSIS
    Build the figures for and write 90-gap-analysis.md.

.DESCRIPTION
    A step of the Blueprint renderer. Steps run in order and pass their results
    to later ones through the render context, so this one may also prepare
    figures that a later page uses.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/GapAnalysis/Write-BlueprintGapAnalysisSection.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.
function Write-BlueprintGapAnalysisSection {
    <#
    .SYNOPSIS
        Build the figures for and write 90-gap-analysis.md.

    .PARAMETER Context
        The render context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the render context.
    $gapByCategory = $Context.gapByCategory
    $gapFindings = $Context.gapFindings
    $m = $Context.m
    $maturity = $Context.maturity
    $maturityOk = $Context.maturityOk
    $n = $Context.n
    $ResourcesRoot = $Context.ResourcesRoot
    $t = $Context.t

    # ---------------------------------------------------------------------------
    # Section: 90 — gap analysis
    # ---------------------------------------------------------------------------
    # Findings and maturity are one assessment: each finding names the maturity
    # criterion it decides, if any, and what closing it does to the score.
    $findingMaturity = Get-FindingMaturityLink -CriteriaPath (Join-Path $ResourcesRoot 'maturity-criteria.json') -Maturity $(if ($maturityOk) { $maturity } else { $null })
    $gapRows = $gapFindings | ForEach-Object {
        [pscustomobject]@{
            ID       = "[$($_.Id)](#$(($_.Id).ToLower()))"
            Severity = $_.Severity
            Category = $_.Category
            Title    = $_.Title
            Maturity = Format-FindingMaturityShort $(if ($findingMaturity.ContainsKey($_.Id)) { @($findingMaturity[$_.Id]) } else { $null })
        }
    }

    # Findings landscape — grouped bar by category × severity. Sort categories
    # by Warning-then-Info count desc so the worst buckets land on the left.
    $catOrder = $gapByCategory.Keys | Sort-Object {
        -(1000 * ($gapByCategory[$_].Critical) + 10 * ($gapByCategory[$_].Warning) + ($gapByCategory[$_].Info))
    }, { $_ }
    $catAxis = ($catOrder | ForEach-Object { "`"$_`"" }) -join ', '
    $catWarn = ($catOrder | ForEach-Object { $gapByCategory[$_].Warning }) -join ', '
    $catInfo = ($catOrder | ForEach-Object { $gapByCategory[$_].Info }) -join ', '
    $catMax = 1
    foreach ($c in $catOrder) {
        $t = $gapByCategory[$c].Warning + $gapByCategory[$c].Info + $gapByCategory[$c].Critical
        if ($t -gt $catMax) { $catMax = $t }
    }

    Write-BlueprintSection '90-gap-analysis.md' (@"
$(Format-Banner -Title "Gap Analysis")

The gap engine compares the live workspace against the rule set in [Private/Resources/best-practices.json](https://github.com/noodlemctwoodle/Sentinel-As-Code/blob/main/Modules/iSOCBlueprint/Engine/Private/Resources/best-practices.json). Each row is a Test-* function in [Private/GapChecks.ps1](https://github.com/noodlemctwoodle/Sentinel-As-Code/blob/main/Modules/iSOCBlueprint/Engine/Private/GapChecks.ps1), and adding a new rule is a two-line change.

Findings and the [maturity assessment](91-maturity-assessment.md) are one assessment seen two ways: a finding says what is wrong now, a maturity criterion scores the capability it leaves missing. Each finding below says which criterion it decides and what closing it does to the overall score; a finding no criterion reads is a hygiene or cost check that does not move the score.

## Findings landscape

``````mermaid
xychart-beta
    title "Findings by category, split by severity"
    x-axis [$catAxis]
    y-axis "Findings" 0 --> $($catMax + 1)
    bar "Warning" [$catWarn]
    bar "Info"    [$catInfo]
``````

**$(Format-BlueprintPlural $gapFindings.Count 'finding').** Categories sorted worst-first (Critical → Warning → Info weighting). Each bar is a category; adjacent Warning + Info bars per category make the severity mix visible at a glance.

## Findings summary

Each ID links to the detail card below, where the full evidence, remediation and reference links live. ``Maturity`` is the overall-score lift from closing the finding and the area it counts in, or Not scored for a hygiene or cost check. Sorted by severity first, then by category.

$(if ($gapRows.Count -gt 0) { Format-BlueprintTable -Items $gapRows -Columns 'ID','Severity','Category','Title','Maturity' } else { '_No findings: a clean run._' })

## Findings detail

$(if ($gapFindings.Count -gt 0) {
    ($gapFindings | ForEach-Object { @"
<a id="$($_.Id.ToLower())"></a>

### $($_.Id): $($_.Title)

**Severity:** $($_.Severity)  ·  **Category:** $($_.Category)

**Maturity:** $(Format-BlueprintFindingMaturity $_.Id)

**Evidence**

$(Format-BlueprintGapEvidence $_.Evidence)

**Remediation**

$($_.Remediation)

**Reference:** $(Format-BlueprintGapLearnLink $_.Learn)

---
"@ }) -join [Environment]::NewLine
} else { '' })
"@)

    # Left in the render context for later sections.
    if (Get-Variable -Name 't' -Scope 0 -ErrorAction Ignore) { $Context.t = $t }
}

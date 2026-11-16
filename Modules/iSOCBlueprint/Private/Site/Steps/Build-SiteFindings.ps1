#Requires -Version 7.6

<#
.SYNOPSIS
    Rank the gap findings and build the findings list.

.DESCRIPTION
    A step of the SharePoint site build. Steps run in order and pass their results
    to later ones through the build context.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Site/Steps/Build-SiteFindings.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-16
    Component:    iSOC Blueprint, SharePoint site build
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Build-SiteFindings {
    <#
    .SYNOPSIS
        Rank the gap findings and build the findings list.

    .PARAMETER Context
        The build context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the build context.
    $gap = $Context.gap
    $resourcesFolder = $Context.resourcesFolder

    # ---- Findings ----
    $sevRank = @{ 'Critical' = 0; 'Error' = 1; 'Warning' = 2; 'Info' = 3; 'Informational' = 3 }
    $bySeverity = @{}
    $byCategory = @{}
    foreach ($f in $gap) {
        if (-not $f) { continue }
        $s = if ($f.Severity) { [string]$f.Severity } else { 'Info' }
        $c = if ($f.Category) { [string]$f.Category } else { 'Other' }
        if (-not $bySeverity.ContainsKey($s)) { $bySeverity[$s] = 0 }; $bySeverity[$s]++
        if (-not $byCategory.ContainsKey($c)) { $byCategory[$c] = 0 }; $byCategory[$c]++
    }
    # Each finding carries the maturity criteria it decides, so the dashboard's
    # Assessment tab can show what closing it does to the score.
    $findingMaturity = Get-FindingMaturityLink -CriteriaPath (Join-Path $resourcesFolder 'Data/maturity-criteria.json') -Maturity (Read-SiteRaw 'maturity.json')
    $findingList = @()
    foreach ($f in ($gap | Where-Object { $_ } | Sort-Object { if ($sevRank.ContainsKey([string]$_.Severity)) { $sevRank[[string]$_.Severity] } else { 5 } }, Id)) {
        $findingList += [ordered]@{
            id          = $f.Id
            legacyId    = $(if ($f.PSObject.Properties['LegacyId'] -and $f.LegacyId) { [string]$f.LegacyId } else { $null })
            area        = $(if ($f.PSObject.Properties['Area'] -and $f.Area) { [string]$f.Area } else { $null })
            title       = $f.Title
            severity    = [string]$f.Severity
            category    = [string]$f.Category
            # An older snapshot's "?" for an unnamed principal, in words, as on the report page.
            evidence    = $(if ($f.Evidence) { [regex]::Replace([string]$f.Evidence, '(?<=[:;]\s)\?(?=\s*(;|\.?\s*$))', 'Unnamed (no name in this snapshot)') } else { $f.Evidence })
            remediation = $f.Remediation
            learn       = $f.Learn
            maturity    = @($(if ($findingMaturity.ContainsKey([string]$f.Id)) { @($findingMaturity[[string]$f.Id]) } else { @() }) | ForEach-Object {
                    [ordered]@{ criterionId = $_.CriterionId; name = $_.Name; area = $_.Area; areaName = $_.AreaName; status = $_.Status; lift = $_.Lift; shared = $_.Shared }
                })
        }
    }
    $findings = [ordered]@{
        total      = @($gap | Where-Object { $_ }).Count
        bySeverity = $bySeverity
        byCategory = $byCategory
        items      = $findingList
    }

    # Left in the build context for later steps.
    $Context.findingList = $findingList
    $Context.findings = $findings
}

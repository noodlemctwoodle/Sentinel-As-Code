#Requires -Version 7.6

<#
.SYNOPSIS
    Link each gap-analysis finding to the maturity criteria it decides.

.DESCRIPTION
    Findings (best-practices.json) and maturity criteria
    (maturity-criteria.json) are one assessment seen two ways: a finding
    says what is wrong now, a criterion scores the capability it leaves
    missing. A criterion whose source is a gap rule, directly or inside an
    allOf / anyOf, is decided by that rule's finding. This helper builds the
    finding-to-criteria map and joins each criterion's status and the
    overall lift from closing it from maturity.json, so the gap-analysis
    page and the dashboard can say what fixing a finding does to the
    maturity score. Findings no criterion reads are hygiene and cost checks
    that do not move the score.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Lookup/Get-FindingMaturityLink.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-13
    Version:      0.1.3
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-FindingMaturityLink {
    <#
    .SYNOPSIS
        Map each finding id to the maturity criteria it decides.

    .PARAMETER CriteriaPath
        Path to maturity-criteria.json.

    .PARAMETER Maturity
        The parsed maturity.json, or $null when the run has none (the
        criteria are then listed without status or lift).

    .OUTPUTS
        [hashtable] finding id to an array of [pscustomobject] CriterionId,
        Name, Area, AreaName, Status, Lift and Shared ($true when the
        criterion combines several findings). Keys are case-insensitive; a
        finding absent from the map decides no criterion.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)] [string] $CriteriaPath,
        [AllowNull()] $Maturity
    )

    $map = [System.Collections.Hashtable]::new([StringComparer]::OrdinalIgnoreCase)
    if (-not (Test-Path -LiteralPath $CriteriaPath)) { return $map }
    $doc = Get-Content -LiteralPath $CriteriaPath -Raw | ConvertFrom-Json -Depth 16

    $areaNames = @{}
    foreach ($a in @($doc.areas)) { if ($a -and $a.id) { $areaNames[[string]$a.id] = [string]$a.name } }
    $status = @{}
    $lift = @{}
    if ($Maturity) {
        foreach ($a in @($Maturity.areas)) {
            if (-not $a) { continue }
            if ($a.PSObject.Properties['name'] -and $a.name) { $areaNames[[string]$a.id] = [string]$a.name }
            foreach ($c in @($a.criteria)) { if ($c -and $c.id) { $status[[string]$c.id] = [string]$c.status } }
        }
        foreach ($r in @($Maturity.roadmap)) { if ($r -and $r.criterionId) { $lift[[string]$r.criterionId] = $r.overallLift } }
    }

    # Every gap rule a criterion's source names, through allOf and anyOf.
    $rulesOf = {
        param($Source)
        if (-not $Source) { return }
        switch ([string]$Source.kind) {
            'gapRule' { [string]$Source.rule }
            { $_ -in 'allOf', 'anyOf' } { foreach ($s in @($Source.sources)) { & $rulesOf $s } }
        }
    }

    foreach ($c in @($doc.criteria)) {
        if (-not $c -or -not $c.id) { continue }
        $rules = @(& $rulesOf $c.source | Where-Object { $_ } | Sort-Object -Unique)
        foreach ($rule in $rules) {
            if (-not $map.ContainsKey($rule)) { $map[$rule] = [System.Collections.Generic.List[object]]::new() }
            $map[$rule].Add([pscustomobject]@{
                    CriterionId = [string]$c.id
                    Name        = [string]$c.name
                    Area        = [string]$c.area
                    AreaName    = $(if ($areaNames.ContainsKey([string]$c.area)) { $areaNames[[string]$c.area] } else { [string]$c.area })
                    Status      = $(if ($status.ContainsKey([string]$c.id)) { $status[[string]$c.id] } else { $null })
                    Lift        = $(if ($lift.ContainsKey([string]$c.id)) { [double]$lift[[string]$c.id] } else { $null })
                    Shared      = ($rules.Count -gt 1)
                })
        }
    }
    foreach ($k in @($map.Keys)) { $map[$k] = $map[$k].ToArray() }
    return $map
}

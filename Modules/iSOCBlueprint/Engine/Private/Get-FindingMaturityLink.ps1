#Requires -Version 7.2

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
    File:         Modules/iSOCBlueprint/Engine/Private/Get-FindingMaturityLink.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-13
    Version:      0.1.1
    Last Updated: 2026-10-15
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

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

function Format-FindingMaturityShort {
    <#
    .SYNOPSIS
        A short label for a finding's effect on the maturity score: the
        lift and area when closing it lifts the score, the area alone when
        the criterion carries no lift, 'Not scored' when no criterion reads
        the finding.

    .PARAMETER Links
        The finding's entry from Get-FindingMaturityLink, or $null.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowNull()] [object[]] $Links)

    if (-not $Links -or @($Links).Count -eq 0) { return 'Not scored' }
    $parts = @($Links | ForEach-Object {
            # The lift to two places, as the roadmap, the finding cards and
            # every score on the pages write it.
            if ($null -ne $_.Lift -and $_.Lift -gt 0) { '+{0} to {1}' -f ([double]$_.Lift).ToString('0.00', [System.Globalization.CultureInfo]::InvariantCulture), $_.Area }
            else { $_.Area }
        } | Sort-Object -Unique)
    return ($parts -join '; ')
}

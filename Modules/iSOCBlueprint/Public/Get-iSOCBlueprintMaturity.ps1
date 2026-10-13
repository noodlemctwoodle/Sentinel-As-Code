#Requires -Version 7.2

<#
.SYNOPSIS
    Get-iSOCBlueprintMaturity: score an inventory against the maturity
    model.

.DESCRIPTION
    Offline. Runs the gap analysis and then the maturity assessment
    (Engine/Private/Get-SentinelMaturity.ps1 with maturity-criteria.json)
    and returns the assessment as one object.

.NOTES
    File:         Modules/iSOCBlueprint/Public/Get-iSOCBlueprintMaturity.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-13
    Version:      0.1.0
    Last Updated: 2026-10-13
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter and
    per-example detail lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCBlueprintMaturity {
    <#
    .SYNOPSIS
        The maturity assessment for a Blueprint inventory.

    .DESCRIPTION
        Scores each maturity criterion from the inventory and the gap
        analysis, rolls the criteria up into areas and an overall level
        from 1 (Initial) to 5, and builds the roadmap of criteria to close
        to reach the target level, largest lift first. Criteria whose input
        was not captured are Unknown and never count against the
        workspace. The scoring runs now, against the module's current
        criteria; the collector saved its own run's assessment as
        _raw/maturity.json.

    .PARAMETER Path
        The workspace folder holding _raw/, or the _raw folder itself.

    .PARAMETER TargetMaturityLevel
        Level, 1 to 5, the workspace is aiming for. Sets the gap and the
        roadmap. Defaults to 3 (Established).

    .OUTPUTS
        [pscustomobject] The assessment, the same shape as _raw/maturity.json:
        the overall score and level, the areas with their criteria, and the
        roadmap.

    .EXAMPLE
        (Get-iSOCBlueprintMaturity -Path ./SecurityDocs/law-sentinel-prod).roadmap |
            Select-Object -First 5

        The five criteria that lift the score most.

    .EXAMPLE
        Get-iSOCBlueprintMaturity -Path ./SecurityDocs/law-sentinel-prod -TargetMaturityLevel 4

        Assesses the workspace against level 4 instead of 3.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string] $Path,

        [ValidateRange(1, 5)]
        [int] $TargetMaturityLevel = 3
    )

    process {
        $raw = Resolve-iSOCBlueprintRawPath -Path $Path
        $engine = $script:iSOCBlueprintEngineRoot
        $resources = Join-Path $engine 'Private/Resources'
        . (Join-Path $engine 'Private/Get-SentinelGap.ps1')
        . (Join-Path $engine 'Private/Get-SentinelMaturity.ps1')

        $outcomes = [System.Collections.Generic.List[object]]::new()
        $null = Get-SentinelGap -InputRoot $raw -ResourcesRoot $resources `
            -RulesPath (Join-Path $resources 'best-practices.json') `
            -GapChecksPath (Join-Path $engine 'Private/GapChecks.ps1') `
            -OutcomeCollector $outcomes

        Get-SentinelMaturity -InputRoot $raw -ResourcesRoot $resources `
            -CriteriaPath (Join-Path $resources 'maturity-criteria.json') `
            -GapOutcomes $outcomes.ToArray() `
            -TargetLevel $TargetMaturityLevel
    }
}

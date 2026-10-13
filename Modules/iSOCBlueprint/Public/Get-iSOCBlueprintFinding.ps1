#Requires -Version 7.2

<#
.SYNOPSIS
    Get-iSOCBlueprintFinding: run the gap analysis over an inventory.

.DESCRIPTION
    Offline. Runs the engine's gap analysis (Engine/Private/Get-SentinelGap.ps1
    with the rules in best-practices.json) and returns the findings as
    objects.

.NOTES
    File:         Modules/iSOCBlueprint/Public/Get-iSOCBlueprintFinding.ps1
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

function Get-iSOCBlueprintFinding {
    <#
    .SYNOPSIS
        The gap-analysis findings for a Blueprint inventory.

    .DESCRIPTION
        Runs every best-practice rule against the inventory and returns the
        findings that fire. The rules run now, against the module's current
        rule set, so an inventory collected earlier can be re-assessed after
        the rules change without collecting again. The collector saved its
        own run's findings as _raw/gap-analysis.json.

    .PARAMETER Path
        The workspace folder holding _raw/, or the _raw folder itself.

    .PARAMETER Outcome
        Return one outcome per rule instead (Fired, Passed, Errored or
        Undefined), so a rule that passed can be told from one that could
        not run.

    .OUTPUTS
        [pscustomobject] One per finding: Id (for example SAC-LOG-03),
        Area, Title, Category, Severity, Evidence, Detail, Remediation,
        Learn and CheckName. With -Outcome, one per rule: Id, Check,
        Outcome and Message.

    .EXAMPLE
        Get-iSOCBlueprintFinding -Path ./SecurityDocs/law-sentinel-prod |
            Group-Object Severity

        Counts the findings by severity.

    .EXAMPLE
        Get-iSOCBlueprintFinding -Path ./SecurityDocs/law-sentinel-prod -Outcome |
            Where-Object Outcome -eq 'Errored'

        Lists the rules that could not be evaluated from this inventory.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string] $Path,

        [switch] $Outcome
    )

    process {
        $raw = Resolve-iSOCBlueprintRawPath -Path $Path
        $engine = $script:iSOCBlueprintEngineRoot
        $resources = Join-Path $engine 'Private/Resources'
        . (Join-Path $engine 'Private/Get-SentinelGap.ps1')

        $outcomes = [System.Collections.Generic.List[object]]::new()
        $findings = Get-SentinelGap -InputRoot $raw -ResourcesRoot $resources `
            -RulesPath (Join-Path $resources 'best-practices.json') `
            -GapChecksPath (Join-Path $engine 'Private/GapChecks.ps1') `
            -OutcomeCollector $outcomes

        if ($Outcome) { $outcomes.ToArray() } else { $findings }
    }
}

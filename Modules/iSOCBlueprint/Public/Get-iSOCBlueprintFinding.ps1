#Requires -Version 7.6

<#
.SYNOPSIS
    Get-iSOCBlueprintFinding: run the gap analysis over an inventory.

.DESCRIPTION
    Offline. Runs the engine's gap analysis (Private/GapAnalysis/Get-SentinelGap.ps1
    with the rules in best-practices.json) and returns the findings as
    objects.

.NOTES
    File:         Modules/iSOCBlueprint/Public/Get-iSOCBlueprintFinding.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-13
    Version:      0.1.3
    Last Updated: 2026-11-16
    Requires:     PowerShell 7.6+

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
        The run's folder holding _raw/, a workspace folder holding day
        folders (the newest day is used), or the _raw folder itself.

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
        $resources = Join-Path $script:iSOCBlueprintResourcesRoot 'Data'

        $outcomes = [System.Collections.Generic.List[object]]::new()
        $findings = Get-SentinelGap -InputRoot $raw -ResourcesRoot $resources `
            -RulesPath (Join-Path $resources 'best-practices.json') `
            -OutcomeCollector $outcomes

        if ($Outcome) { $outcomes.ToArray() } else { $findings }
    }
}

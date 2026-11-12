#Requires -Version 7.6

<#
.SYNOPSIS
    Gap rule outcomes and findings evidence, keyed by rule id.

.DESCRIPTION
    Rule outcomes: the collector passes them in; a standalone run reads the
    file the gap engine wrote. Evidence for Gap criteria comes from the
    findings file so the maturity page can quote it.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Maturity/Criteria/Read-MaturityOutcome.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, Maturity Engine
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function Read-MaturityOutcome {
    <#
    .SYNOPSIS
        Build the rule-id lookups the criteria resolve against.

    .PARAMETER InputRoot
        The _raw folder; gap-checks.json and gap-analysis.json are read from it.

    .PARAMETER GapOutcomes
        The per-rule outcomes from Get-SentinelGap -OutcomeCollector. When
        omitted, gap-checks.json in InputRoot is read instead.

    .OUTPUTS
        A hashtable with OutcomeById (rule id to outcome) and EvidenceById
        (rule id to the finding's evidence text).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [string] $InputRoot,
        [Parameter(Mandatory = $false)] [AllowNull()] [object[]] $GapOutcomes
    )

    $outcomes = $GapOutcomes
    if ($null -eq $outcomes) {
        $checksPath = Join-Path $InputRoot 'gap-checks.json'
        if (Test-Path $checksPath) {
            $raw = Get-Content $checksPath -Raw
            if (-not [string]::IsNullOrWhiteSpace($raw)) { $outcomes = @($raw | ConvertFrom-Json -Depth 8) }
        }
    }
    $outcomeById = @{}
    foreach ($o in @($outcomes)) {
        if ($null -eq $o) { continue }
        $id = [string](Get-MaturityPropertyValue $o 'Id' '')
        if ($id) { $outcomeById[$id] = [string](Get-MaturityPropertyValue $o 'Outcome' '') }
    }
    $evidenceById = @{}
    $findingsPath = Join-Path $InputRoot 'gap-analysis.json'
    if (Test-Path $findingsPath) {
        $raw = Get-Content $findingsPath -Raw
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            foreach ($f in @($raw | ConvertFrom-Json -Depth 16)) {
                if ($null -eq $f) { continue }
                $id = [string](Get-MaturityPropertyValue $f 'Id' '')
                if ($id) { $evidenceById[$id] = [string](Get-MaturityPropertyValue $f 'Evidence' '') }
            }
        }
    }
    return @{ OutcomeById = $outcomeById; EvidenceById = $evidenceById }
}

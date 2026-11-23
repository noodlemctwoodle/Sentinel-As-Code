#Requires -Version 7.6

<#
.SYNOPSIS
    Gap-analysis engine. Loads the best-practices ruleset, builds an in-memory
    Inventory object from the _raw/ JSON files, dispatches each Test-* function and
    aggregates findings.

.DESCRIPTION
    Pure data-in/data-out, testable end-to-end with fixture files.

    The check functions (Private/Gap) and the lookups they read
    (Private/Lookup, Private/Format) are loaded with the module, or by the
    caller when it runs this on its own; a rule whose check is not defined
    is reported as Undefined.

    Usage:
        $findings = Get-SentinelGap -InputRoot './SecurityDocs/myws/_raw' `
                                    -ResourcesRoot './Modules/iSOCBlueprint/Resources/Data' `
                                    -RulesPath './Modules/iSOCBlueprint/Resources/Data/best-practices.json'

    Each finding is a [pscustomobject] with these fields:
        Id           : SAC-LOG-03
        Title        : Daily cap not configured...
        Category     : Cost
        Severity     : Warning
        Evidence     : Free-text from the check function
        Detail       : Rule-specific detail object (or $null)
        Remediation  : From best-practices.json
        Learn        : URL from best-practices.json
        CheckName    : Name of the Test-* function
        PassedAt     : ISO-8601 timestamp of the run

    Pass -OutcomeCollector (an empty List[object]) to also receive one
    record per rule saying what happened to its check:
        Id           : SAC-LOG-03
        Check        : Name of the Test-* function
        Outcome      : Fired | Passed | Errored | Undefined
        Message      : Error text for Errored / Undefined, else $null

    The findings alone cannot tell "the check ran and passed" from "the
    check threw" or "the check does not exist", because all three leave no
    finding. The SharePoint findings list needs that difference: it only
    marks a finding Resolved when its check actually passed.

    Inventory fields read from files that the collector only writes when
    the capture succeeds (rule-effectiveness, playbook-runs, hunts and so
    on) are always arrays: a missing or empty file gives an empty array.
    Inventory.RawFiles lists the JSON files that exist, so a check can
    tell "the capture did not run" (stay quiet) from "it ran and found
    nothing" (which may itself be the finding).

.NOTES
    File:         Modules/iSOCBlueprint/Private/GapAnalysis/Get-SentinelGap.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-05-06
    Version:      0.7.6
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-SentinelGap {
    <#
    .SYNOPSIS
        Run every rule's check against the inventory built from a run's raw
        files and return the findings.

    .DESCRIPTION
        Each rule in the ruleset names a check function. A check that returns a
        result gives a finding; one that returns $null passes and gives none. A
        check that throws, or is not defined, is warned about and gives none.
        {lookback} and {recent} in a rule's title and remediation are replaced
        with the run's window in days. When OutcomeCollector is given, every
        rule adds a record to it: Id, Check, Outcome (Fired, Passed, Errored or
        Undefined) and Message (the error text for Errored and Undefined, else
        $null).

    .PARAMETER InputRoot
        The run's _raw folder of JSON files, read into the inventory by
        New-InventoryFromRaw. An error when it does not exist.

    .PARAMETER ResourcesRoot
        The folder of reference data files the inventory also reads. An error
        when it does not exist.

    .PARAMETER RulesPath
        The best-practices JSON file; its rules array lists the rules to run.
        An error when it does not exist.

    .PARAMETER OutcomeCollector
        An empty List[object] that receives one outcome record per rule. When it
        is omitted no outcomes are recorded.

    .OUTPUTS
        [pscustomobject[]] One finding per rule whose check returned a result,
        with Id, LegacyId, Area, Title, Category, Severity, Evidence, Detail,
        Remediation, Learn, CheckName and PassedAt. An empty array when nothing
        fired.
    #>
    [OutputType([object[]])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputRoot,

        [Parameter(Mandatory = $true)]
        [string]$ResourcesRoot,

        [Parameter(Mandatory = $true)]
        [string]$RulesPath,

        [Parameter(Mandatory = $false)]
        [System.Collections.Generic.List[object]]$OutcomeCollector
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    if (-not (Test-Path $RulesPath)) { throw "Rules file not found: $RulesPath" }
    if (-not (Test-Path $InputRoot)) { throw "Input root not found: $InputRoot" }
    if (-not (Test-Path $ResourcesRoot)) { throw "Resources root not found: $ResourcesRoot" }

    $rules = (Get-Content $RulesPath -Raw | ConvertFrom-Json).rules

    $inventory = New-InventoryFromRaw -InputRoot $InputRoot -ResourcesRoot $ResourcesRoot

    $recordOutcome = {
        param($Id, $Check, $Outcome, $Message)
        if ($null -ne $OutcomeCollector) {
            $OutcomeCollector.Add([pscustomobject]@{ Id = $Id; Check = $Check; Outcome = $Outcome; Message = $Message })
        }
    }

    $findings = @()
    foreach ($rule in $rules) {
        $checkName = $rule.check
        $cmd = Get-Command -Name $checkName -CommandType Function -ErrorAction SilentlyContinue
        if (-not $cmd) {
            Write-Warning "Get-SentinelGap: check '$checkName' (rule $($rule.id)) not defined"
            & $recordOutcome $rule.id $checkName 'Undefined' "Check '$checkName' is not defined."
            continue
        }

        try {
            $result = & $cmd -Inventory $inventory
        } catch {
            Write-Warning "Get-SentinelGap: rule $($rule.id) ($checkName) threw: $($_.Exception.Message)"
            & $recordOutcome $rule.id $checkName 'Errored' $_.Exception.Message
            continue
        }

        & $recordOutcome $rule.id $checkName $(if ($null -ne $result) { 'Fired' } else { 'Passed' }) $null

        if ($null -ne $result) {
            # A rule's title and remediation name the window as {lookback}
            # and {recent}; they read as the run's window here.
            $window = $inventory.Window
            $inWindow = { param($Text) if ($null -eq $Text) { return $Text }
                $t = [string]$Text
                $t = $t.Replace('{lookback}', $(if ($window.Days -eq 1) { '1 day' } else { "$($window.Days) days" }))
                $t.Replace('{recent}', $(if ($window.RecentDays -eq 1) { '1 day' } else { "$($window.RecentDays) days" })) }
            $findings += [pscustomobject]@{
                Id          = $rule.id
                LegacyId    = $(if ($rule.PSObject.Properties['legacyId']) { [string]$rule.legacyId } else { $null })
                Area        = $(if ($rule.PSObject.Properties['area']) { [string]$rule.area } else { $null })
                Title       = & $inWindow $rule.title
                Category    = $rule.category
                Severity    = $rule.severity
                Evidence    = $result.Evidence
                Detail      = $result.Detail
                Remediation = & $inWindow $rule.remediation
                Learn       = $rule.learn
                CheckName   = $checkName
                PassedAt    = (Get-Date).ToUniversalTime().ToString('o')
            }
        }
    }

    return , $findings
}

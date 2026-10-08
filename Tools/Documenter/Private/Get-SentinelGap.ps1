#Requires -Version 7.2

<#
.SYNOPSIS
    Gap-analysis engine. Loads the best-practices ruleset, builds an in-memory
    Inventory object from the _raw/ JSON files, dispatches each Test-* function and
    aggregates findings.

.DESCRIPTION
    Pure data-in/data-out, testable end-to-end with fixture files.

    Usage:
        $findings = Get-SentinelGap -InputRoot './SecurityDocs/myws/_raw' `
                                    -ResourcesRoot './Tools/Documenter/Private/Resources' `
                                    -RulesPath './Tools/Documenter/Private/Resources/best-practices.json' `
                                    -GapChecksPath './Tools/Documenter/Private/GapChecks.ps1'

    Each finding is a [pscustomobject] with these fields:
        Id           : SENT-001
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
        Id           : SENT-001
        Check        : Name of the Test-* function
        Outcome      : Fired | Passed | Errored | Undefined
        Message      : Error text for Errored / Undefined, else $null

    The findings alone cannot tell "the check ran and passed" from "the
    check threw" or "the check does not exist", because all three leave no
    finding. The SharePoint findings list needs that difference: it only
    marks a finding Resolved when its check actually passed.

.NOTES
    File:         Tools/Documenter/Private/Get-SentinelGap.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-05-06
    Version:      0.2.0
    Last Updated: 2026-10-08
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function Get-SentinelGap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputRoot,

        [Parameter(Mandatory = $true)]
        [string]$ResourcesRoot,

        [Parameter(Mandatory = $true)]
        [string]$RulesPath,

        [Parameter(Mandatory = $true)]
        [string]$GapChecksPath,

        [Parameter(Mandatory = $false)]
        [System.Collections.Generic.List[object]]$OutcomeCollector
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    if (-not (Test-Path $RulesPath))      { throw "Rules file not found: $RulesPath" }
    if (-not (Test-Path $GapChecksPath))  { throw "GapChecks not found: $GapChecksPath" }
    if (-not (Test-Path $InputRoot))      { throw "Input root not found: $InputRoot" }
    if (-not (Test-Path $ResourcesRoot))  { throw "Resources root not found: $ResourcesRoot" }

    # Dot-source the gap check functions into the current scope.
    . $GapChecksPath

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
            Write-Warning "Get-SentinelGap: check '$checkName' (rule $($rule.id)) not defined in $GapChecksPath"
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
            $findings += [pscustomobject]@{
                Id          = $rule.id
                Title       = $rule.title
                Category    = $rule.category
                Severity    = $rule.severity
                Evidence    = $result.Evidence
                Detail      = $result.Detail
                Remediation = $rule.remediation
                Learn       = $rule.learn
                CheckName   = $checkName
                PassedAt    = (Get-Date).ToUniversalTime().ToString('o')
            }
        }
    }

    return ,$findings
}

function New-InventoryFromRaw {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputRoot,

        [Parameter(Mandatory = $true)]
        [string]$ResourcesRoot
    )

    function Read-Json([string]$Name) {
        $p = Join-Path $InputRoot $Name
        if (-not (Test-Path $p)) { return $null }
        $raw = Get-Content $p -Raw
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        return ($raw | ConvertFrom-Json -Depth 32)
    }

    function Read-Resource([string]$Name) {
        $p = Join-Path $ResourcesRoot $Name
        if (-not (Test-Path $p)) { return $null }
        $raw = Get-Content $p -Raw
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        return ($raw | ConvertFrom-Json -Depth 32)
    }

    [pscustomobject]@{
        Workspace              = Read-Json 'workspace.json'
        WorkspaceTables        = @(Read-Json 'workspace-tables.json')
        TablesWithData         = @(Read-Json 'tables-with-data.json')
        Dcrs                   = @(Read-Json 'dcrs.json')
        DiagnosticSettings     = @(Read-Json 'diagnostic-settings.json')
        AlertRules             = @(Read-Json 'alert-rules.json')
        AlertRuleTemplates     = @(Read-Json 'alert-rule-templates.json')
        DataConnectors         = @(Read-Json 'data-connectors-classic.json')
        Settings               = Read-Json  'settings.json'
        UebaDataPresence       = @(Read-Json 'ueba-data-presence.json')
        ContentPackages        = @(Read-Json 'content-packages.json')
        ContentProductPackages = @(Read-Json 'content-product-packages.json')
        DedicatedCluster       = Read-Json 'dedicated-cluster.json'
        ResourceProviders      = @(Read-Json 'resource-providers.json')
        RbacWorkspace          = @(Read-Json 'rbac-workspace.json')
        PlaybookMiAssignments  = @(Read-Json 'rbac-playbook-mi.json')
        IncidentsMttr          = @(Read-Json 'incidents-mttr.json')
        AnalyticsRuleVolumes   = @(Read-Json 'analytics-rule-volumes.json')
        AutomationRules        = @(Read-Json 'automation-rules.json')
        WorkspaceLocks         = @(Read-Json 'workspace-locks.json')
        AmaMmaMigration        = @(Read-Json 'ama-mma-migration.json')
        MitreTactics           = @((Read-Resource 'mitre-attack.json').tactics)
        MitreTechniques        = @((Read-Resource 'mitre-attack.json').techniques)
        SentinelBenefitTables  = Read-Resource 'sentinel-benefit-tables.json'
        CommitmentTiers        = Read-Resource 'commitment-tiers.json'
    }
}

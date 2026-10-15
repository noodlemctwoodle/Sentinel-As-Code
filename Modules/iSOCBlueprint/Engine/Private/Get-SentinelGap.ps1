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
                                    -ResourcesRoot './Modules/iSOCBlueprint/Engine/Private/Resources' `
                                    -RulesPath './Modules/iSOCBlueprint/Engine/Private/Resources/best-practices.json' `
                                    -GapChecksPath './Modules/iSOCBlueprint/Engine/Private/GapChecks.ps1'

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
    File:         Modules/iSOCBlueprint/Engine/Private/Get-SentinelGap.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-05-06
    Version:      0.7.1
    Last Updated: 2026-10-15
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# The inventory loads the connector catalogue, whichever checks file runs.
. (Join-Path $PSScriptRoot 'Get-ConnectorCatalogue.ps1')
# Template to Content Hub solution, so checks can leave out templates only a
# deprecated solution ships.
. (Join-Path $PSScriptRoot 'Get-TemplateSolution.ps1')

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

    # Always an array: a missing file, an empty file and a JSON "[]" all give
    # @(), so checks can take .Count without guarding. Checks that need to
    # know whether the file exists at all consult RawFiles.
    function Read-JsonArray([string]$Name) {
        $data = Read-Json $Name
        if ($null -eq $data) { return ,@() }
        return ,@($data)
    }

    $rawFiles = @(Get-ChildItem -Path $InputRoot -Filter '*.json' -File | ForEach-Object Name)
    # The window the KQL captures read (run-context.json). A run collected
    # before the setting existed read 30 days, its recent figures 7.
    $runContext = Read-Json 'run-context.json'
    $lookback = 30
    if ($runContext -and $runContext.PSObject.Properties['LookbackDays'] -and [int]$runContext.LookbackDays -ge 1) { $lookback = [int]$runContext.LookbackDays }
    $recent = [math]::Min(7, $lookback)
    if ($runContext -and $runContext.PSObject.Properties['RecentDays'] -and [int]$runContext.RecentDays -ge 1) { $recent = [int]$runContext.RecentDays }

    # When the run collected: the window ends here, so a re-render later
    # judges the same days.
    $asOf = [datetime]::UtcNow
    if ($runContext -and $runContext.PSObject.Properties['StartedAtUtc'] -and $runContext.StartedAtUtc) {
        $parsed = [datetime]::MinValue
        if ($runContext.StartedAtUtc -is [datetime]) { $asOf = $runContext.StartedAtUtc.ToUniversalTime() }
        elseif ([datetime]::TryParse([string]$runContext.StartedAtUtc, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$parsed)) { $asOf = $parsed }
    }

    [pscustomobject]@{
        RawFiles               = $rawFiles
        Window                 = [pscustomobject]@{ Days = $lookback; RecentDays = $recent; AsOfUtc = $asOf }
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
        RuleTableReferences    = Read-JsonArray 'rule-table-references.json'
        TemplateTableReferences = Read-JsonArray 'template-table-references.json'
        RuleEffectiveness      = Read-JsonArray 'rule-effectiveness.json'
        RulesFired             = Read-JsonArray 'rules-fired.json'
        PlaybookRuns           = Read-JsonArray 'playbook-runs.json'
        Hunts                  = Read-JsonArray 'hunts.json'
        RuleHealth             = Read-JsonArray 'rule-health.json'
        CustomDetectionRefs    = Read-JsonArray 'custom-detection-table-references.json'
        Bookmarks              = Read-JsonArray 'bookmarks.json'
        BookmarksCount         = Read-Json 'bookmarks-count.json'
        BookmarksFromLogs      = Read-JsonArray 'bookmarks-from-logs.json'
        IncidentsSummary       = Read-JsonArray 'incidents-summary.json'
        AzureDiagnosticsCategories = Read-JsonArray 'azure-diagnostics-categories.json'
        ThreatIntelCounts      = Read-JsonArray 'threat-intel-counts.json'
        SummaryRules           = Read-JsonArray 'summary-rules.json'
        Watchlists             = Read-JsonArray 'watchlists.json'
        SecurityEventDuplicates = Read-JsonArray 'security-event-duplicates.json'
        CefInSyslog            = Read-JsonArray 'cef-in-syslog.json'
        LaQueryLogs            = Read-JsonArray 'la-query-logs.json'
        TableQueryUsage        = Read-JsonArray 'table-query-usage.json'
        MitreTactics           = @((Read-Resource 'mitre-attack.json').tactics)
        MitreTechniques        = @((Read-Resource 'mitre-attack.json').techniques)
        SentinelBenefitTables  = Read-Resource 'sentinel-benefit-tables.json'
        CommitmentTiers        = Read-Resource 'commitment-tiers.json'
        ConnectorCatalogue     = Import-ConnectorCatalogue -Path (Join-Path $ResourcesRoot 'connector-catalogue.json')
    }
}

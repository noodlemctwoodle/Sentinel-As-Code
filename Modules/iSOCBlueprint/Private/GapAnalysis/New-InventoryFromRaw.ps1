#Requires -Version 7.6

<#
.SYNOPSIS
    New-InventoryFromRaw, a helper of Get-SentinelGap.

.DESCRIPTION
    One of the helpers beside Get-SentinelGap.ps1, which describes the whole.

.NOTES
    File:         Modules/iSOCBlueprint/Private/GapAnalysis/New-InventoryFromRaw.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-05-06
    Version:      0.1.0
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

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

    $rawFiles = @(Get-ChildItem -Path $InputRoot -Filter '*.json' -File | ForEach-Object { $_.Name })
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
        elseif ([datetime]::TryParse([string]$runContext.StartedAtUtc, [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$parsed)) {
            $asOf = $parsed
        }
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

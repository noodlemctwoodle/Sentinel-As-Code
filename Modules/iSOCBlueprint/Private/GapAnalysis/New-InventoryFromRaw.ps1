#Requires -Version 7.6

<#
.SYNOPSIS
    Build the inventory the gap checks read from a run's raw JSON files

.DESCRIPTION
    One of the helpers beside Get-SentinelGap.ps1, which describes the whole.

.NOTES
    File:         Modules/iSOCBlueprint/Private/GapAnalysis/New-InventoryFromRaw.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-05-06
    Version:      0.1.1
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function New-InventoryFromRaw {
    <#
    .SYNOPSIS
        Build the inventory the gap checks read, from a run's raw JSON files and
        the reference data.

    .DESCRIPTION
        Each property holds the parsed content of one JSON file under
        InputRoot, or of a reference file under ResourcesRoot. The properties
        read with Read-JsonArray are always arrays, empty for a missing or empty
        file; the others hold the parsed JSON, wrapped in an array for most, and
        Read-Json gives $null for a missing or empty file. RawFiles lists the
        JSON files that exist, so a check can tell a capture that did not run
        from one that found nothing. Window holds Days (the look-back),
        RecentDays and AsOfUtc (the run's start time), read from
        run-context.json. Days defaults to 30, RecentDays to 7 or to Days when
        that is smaller, and AsOfUtc to the current time. ConnectorCatalogue
        comes from Import-ConnectorCatalogue.

    .PARAMETER InputRoot
        The folder holding the run's raw JSON files (the _raw folder).

    .PARAMETER ResourcesRoot
        The folder holding the reference data files: mitre-attack.json,
        sentinel-benefit-tables.json, commitment-tiers.json and
        connector-catalogue.json.

    .OUTPUTS
        [pscustomobject] The inventory.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds an object in memory; nothing outside the call changes.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputRoot,

        [Parameter(Mandatory = $true)]
        [string]$ResourcesRoot
    )

    function Read-Json([string]$Name) {
        <#
        .SYNOPSIS
            Parse one JSON file under InputRoot; $null when it is missing or empty.

        .PARAMETER Name
            The file name under InputRoot.
        #>
        $p = Join-Path $InputRoot $Name
        if (-not (Test-Path $p)) { return $null }
        $raw = Get-Content $p -Raw
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        return ($raw | ConvertFrom-Json -Depth 32)
    }

    function Read-Resource([string]$Name) {
        <#
        .SYNOPSIS
            Parse one reference file under ResourcesRoot; $null when it is missing or empty.

        .PARAMETER Name
            The file name under ResourcesRoot.
        #>
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
        <#
        .SYNOPSIS
            Parse one JSON file under InputRoot as an array, empty for a missing or empty file.

        .PARAMETER Name
            The file name under InputRoot.
        #>
        $data = Read-Json $Name
        if ($null -eq $data) { return , @() }
        return , @($data)
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
        RawFiles                   = $rawFiles
        Window                     = [pscustomobject]@{ Days = $lookback; RecentDays = $recent; AsOfUtc = $asOf }
        Workspace                  = Read-Json 'workspace.json'
        WorkspaceTables            = @(Read-Json 'workspace-tables.json')
        TablesWithData             = @(Read-Json 'tables-with-data.json')
        Dcrs                       = @(Read-Json 'dcrs.json')
        DiagnosticSettings         = @(Read-Json 'diagnostic-settings.json')
        AlertRules                 = @(Read-Json 'alert-rules.json')
        AlertRuleTemplates         = @(Read-Json 'alert-rule-templates.json')
        DataConnectors             = @(Read-Json 'data-connectors-classic.json')
        Settings                   = Read-Json 'settings.json'
        UebaDataPresence           = @(Read-Json 'ueba-data-presence.json')
        ContentPackages            = @(Read-Json 'content-packages.json')
        ContentProductPackages     = @(Read-Json 'content-product-packages.json')
        DedicatedCluster           = Read-Json 'dedicated-cluster.json'
        ResourceProviders          = @(Read-Json 'resource-providers.json')
        RbacWorkspace              = @(Read-Json 'rbac-workspace.json')
        PlaybookMiAssignments      = @(Read-Json 'rbac-playbook-mi.json')
        IncidentsMttr              = @(Read-Json 'incidents-mttr.json')
        AnalyticsRuleVolumes       = @(Read-Json 'analytics-rule-volumes.json')
        AutomationRules            = @(Read-Json 'automation-rules.json')
        WorkspaceLocks             = @(Read-Json 'workspace-locks.json')
        AmaMmaMigration            = @(Read-Json 'ama-mma-migration.json')
        RuleTableReferences        = Read-JsonArray 'rule-table-references.json'
        TemplateTableReferences    = Read-JsonArray 'template-table-references.json'
        RuleEffectiveness          = Read-JsonArray 'rule-effectiveness.json'
        RulesFired                 = Read-JsonArray 'rules-fired.json'
        PlaybookRuns               = Read-JsonArray 'playbook-runs.json'
        Hunts                      = Read-JsonArray 'hunts.json'
        RuleHealth                 = Read-JsonArray 'rule-health.json'
        CustomDetectionRefs        = Read-JsonArray 'custom-detection-table-references.json'
        Bookmarks                  = Read-JsonArray 'bookmarks.json'
        BookmarksCount             = Read-Json 'bookmarks-count.json'
        BookmarksFromLogs          = Read-JsonArray 'bookmarks-from-logs.json'
        IncidentsSummary           = Read-JsonArray 'incidents-summary.json'
        AzureDiagnosticsCategories = Read-JsonArray 'azure-diagnostics-categories.json'
        ThreatIntelCounts          = Read-JsonArray 'threat-intel-counts.json'
        SummaryRules               = Read-JsonArray 'summary-rules.json'
        Watchlists                 = Read-JsonArray 'watchlists.json'
        SecurityEventDuplicates    = Read-JsonArray 'security-event-duplicates.json'
        CefInSyslog                = Read-JsonArray 'cef-in-syslog.json'
        LaQueryLogs                = Read-JsonArray 'la-query-logs.json'
        TableQueryUsage            = Read-JsonArray 'table-query-usage.json'
        MitreTactics               = @((Read-Resource 'mitre-attack.json').tactics)
        MitreTechniques            = @((Read-Resource 'mitre-attack.json').techniques)
        SentinelBenefitTables      = Read-Resource 'sentinel-benefit-tables.json'
        CommitmentTiers            = Read-Resource 'commitment-tiers.json'
        ConnectorCatalogue         = Import-ConnectorCatalogue -Path (Join-Path $ResourcesRoot 'connector-catalogue.json')
    }
}

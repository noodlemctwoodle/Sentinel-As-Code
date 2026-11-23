#Requires -Version 7.6

<#
.SYNOPSIS
    Compute every metric the criteria can reference from the _raw captures.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Maturity/Metrics/New-MaturityMetric.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.2
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Maturity Engine
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function New-MaturityMetric {
    <#
    .SYNOPSIS
        Compute every metric the criteria can reference from the _raw
        captures. A metric is $null when its source file is absent, 0 or
        $false when the file exists and holds nothing.

    .PARAMETER InputRoot
        The _raw folder.

    .PARAMETER ResourcesRoot
        The Resources folder, for the MITRE tactic list.

    .OUTPUTS
        [ordered] hashtable, one entry per metric.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds an object in memory; nothing outside the call changes.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'InputRoot', Justification = 'Read inside the nested Read-Json and Read-Row helpers, which the analyser does not follow.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSProvideCommentHelp', '', Justification = 'The five nested helpers are small readers local to this function, and the file is at the 300 line limit, so they carry no help blocks of their own.')]
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory = $true)] [string] $InputRoot,
        [Parameter(Mandatory = $true)] [string] $ResourcesRoot
    )

    function Read-Json([string]$Name) {
        $p = Join-Path $InputRoot $Name
        if (-not (Test-Path $p)) { return $null }
        $raw = Get-Content $p -Raw
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        return ($raw | ConvertFrom-Json -Depth 32)
    }
    # $null when the file is absent; an array (possibly empty) when present.
    function Read-Row([string]$Name) {
        $p = Join-Path $InputRoot $Name
        if (-not (Test-Path $p)) { return $null }
        $data = Read-Json $Name
        if ($null -eq $data) { return , @() }
        return , @($data | Where-Object { $null -ne $_ })
    }
    function Get-RowCount([string]$Name) {
        $rows = Read-Row $Name
        if ($null -eq $rows) { return $null }
        return @($rows).Count
    }
    function Get-RowSum([object]$Rows, [string]$Property, [scriptblock]$Filter = $null) {
        if ($null -eq $Rows) { return $null }
        $total = 0.0
        foreach ($row in @($Rows)) {
            if ($null -ne $Filter -and -not (& $Filter $row)) { continue }
            $total += ConvertTo-MaturityNumber (Get-MaturityPropertyValue $row $Property 0)
        }
        return $total
    }

    $rules = Read-Row 'alert-rules.json'
    $connectors = Read-Row 'data-connectors-classic.json'
    $tables = Read-Row 'tables-with-data.json'
    $schema = Read-Row 'workspace-tables.json'
    $workspace = Read-Json 'workspace.json'
    $settings = Read-Json 'settings.json'
    $health = Read-Row 'sentinel-health-summary.json'
    $incidents = Read-Row 'incidents-summary.json'
    $mttr = Read-Row 'incidents-mttr.json'
    $tiCounts = Read-Row 'threat-intel-counts.json'
    $rbac = Read-Row 'rbac-workspace.json'
    $mitre = $null
    $mitrePath = Join-Path $ResourcesRoot 'mitre-attack.json'
    if (Test-Path $mitrePath) { $mitre = Get-Content $mitrePath -Raw | ConvertFrom-Json -Depth 16 }

    $enabledRules = $null; $customRules = $null; $tacticsCovered = $null
    if ($null -ne $rules) {
        $enabled = @($rules | Where-Object { [bool](Get-MaturityPropertyValue $_ 'properties.enabled' $false) })
        $enabledRules = $enabled.Count
        $customRules = @($enabled | Where-Object {
                ((Get-MaturityPropertyValue $_ 'kind' '') -in @('Scheduled', 'NRT')) -and
                [string]::IsNullOrWhiteSpace([string](Get-MaturityPropertyValue $_ 'properties.alertRuleTemplateName' ''))
            }).Count
        $covered = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($r in $enabled) {
            foreach ($t in @(Get-MaturityPropertyValue $r 'properties.tactics' @())) { if ($t) { [void]$covered.Add([string]$t) } }
        }
        if ($null -ne $mitre -and (Get-MaturityPropertyValue $mitre 'tactics')) {
            $tacticsCovered = @(
                (Get-MaturityPropertyValue $mitre 'tactics') | Where-Object { $covered.Contains([string](Get-MaturityPropertyValue $_ 'sentinelShortName' '')) }
            ).Count
        } else {
            $tacticsCovered = $covered.Count
        }
    }

    $connectorKinds = $null
    if ($null -ne $connectors) {
        $connectorKinds = @($connectors | ForEach-Object { [string](Get-MaturityPropertyValue $_ 'kind' '') })
    }
    function Test-ConnectorKind([string[]]$Kinds) {
        if ($null -eq $connectorKinds) { return $null }
        return (@($connectorKinds | Where-Object { $_ -in $Kinds }).Count -gt 0)
    }

    $entraTablesPresent = $null; $billableGb30d = $null
    if ($null -ne $tables) {
        $billableGb30d = [math]::Round((Get-RowSum $tables 'BillableLast30d'), 2)
        $entraTablesPresent = @($tables | Where-Object {
                $name = [string](Get-MaturityPropertyValue $_ 'DataType' '')
                $ingested7d = if (Test-MaturityProperty $_ 'IngestedLast7d') {
                    Get-MaturityPropertyValue $_ 'IngestedLast7d' 0
                } else { Get-MaturityPropertyValue $_ 'BillableLast7d' 0 }
                ((Get-TableFamily -Table $name) -eq 'Entra ID / Identity') -and ((ConvertTo-MaturityNumber $ingested7d) -gt 0)
            }).Count
    }

    $xdr = Read-Row 'xdr-table-presence.json'
    $xdrTablesPresent = if ($null -eq $xdr) {
        $null
    } else { @($xdr | Where-Object { (ConvertTo-MaturityNumber (Get-MaturityPropertyValue $_ 'RecordCount' 0)) -gt 0 }).Count }

    $entityAnalyticsEnabled = $null
    if ($null -ne $settings) {
        $providers = @(Get-MaturityPropertyValue $settings 'EntityAnalytics.properties.entityProviders' @() | Where-Object { $null -ne $_ })
        $entityAnalyticsEnabled = ($providers.Count -gt 0)
    }

    $incidents30d = $null; $closedIncidents30d = $null
    if ($null -ne $incidents) {
        if (@($incidents).Count -gt 0) {
            $incidents30d = [int](ConvertTo-MaturityNumber (Get-MaturityPropertyValue $incidents[0] 'Count' 0))
            $closedIncidents30d = [int](ConvertTo-MaturityNumber (Get-MaturityPropertyValue $incidents[0] 'Closed' 0))
        } else { $incidents30d = 0; $closedIncidents30d = 0 }
    }
    $mttaMinutes = $null
    if ($null -ne $mttr -and @($mttr).Count -gt 0) {
        $raw = Get-MaturityPropertyValue $mttr[0] 'MTTAMinutes' $null
        if ($null -ne $raw) {
            # avg() over zero acknowledged incidents comes back as the string
            # "NaN"; there is nothing to measure, so the metric stays null and
            # the criterion resolves to Unknown instead of a Gap.
            $parsed = ConvertTo-MaturityNumber $raw
            if (-not [double]::IsNaN($parsed) -and -not [double]::IsInfinity($parsed)) { $mttaMinutes = [math]::Round($parsed, 1) }
        }
    }

    $searchJobs = Get-RowCount 'search-jobs.json'
    $restores = Get-RowCount 'restore-logs.json'
    # A snapshot collected before the collector wrote these two files still
    # has the table list, where search job (_SRCH) and restored (_RST) tables
    # live; read them from there rather than leave the criterion Unknown.
    if ($null -eq $searchJobs -and $null -eq $restores) {
        $tableRows = Read-Row 'workspace-tables.json'
        if ($null -ne $tableRows) {
            $found = Get-SearchRestoreTable -Tables $tableRows
            $searchJobs = @($found.SearchJobs).Count
            $restores = @($found.Restores).Count
        }
    }
    $searchOrRestoreJobs = if ($null -eq $searchJobs -and $null -eq $restores) { $null } else { [int]$searchJobs + [int]$restores }

    $lakeExtendedTables = $null; $tablesWithCustomRetention = $null
    if ($null -ne $schema) {
        $lakeExtendedTables = @($schema | Where-Object {
                $plan = [string](Get-MaturityPropertyValue $_ 'properties.plan' '')
                $interactive = ConvertTo-MaturityNumber (Get-MaturityPropertyValue $_ 'properties.retentionInDays' 0)
                $total = ConvertTo-MaturityNumber (Get-MaturityPropertyValue $_ 'properties.totalRetentionInDays' 0)
                ($plan -in @('DataLake', 'Auxiliary')) -or ($total -gt $interactive)
            }).Count
        $default = if ($null -ne $workspace) {
            ConvertTo-MaturityNumber (Get-MaturityPropertyValue $workspace 'properties.retentionInDays' $null)
        } else { $null }
        $tablesWithCustomRetention = @($schema | Where-Object {
                if (Test-MaturityProperty (Get-MaturityPropertyValue $_ 'properties' $null) 'retentionInDaysAsDefault') {
                    -not [bool](Get-MaturityPropertyValue $_ 'properties.retentionInDaysAsDefault' $true)
                } elseif ($null -ne $default) {
                    (ConvertTo-MaturityNumber (Get-MaturityPropertyValue $_ 'properties.retentionInDays' $default)) -ne $default
                } else { $false }
            }).Count
    }

    $tiIndicators30d = Get-RowSum $tiCounts 'Count'
    $mdtiRows30d = Get-RowSum -Rows $tiCounts -Property 'Count' -Filter {
        param($row) ([string](Get-MaturityPropertyValue $row 'SourceSystem' '')) -match '^Microsoft'
    }
    $tiObjects30d = Get-RowSum (Read-Row 'threat-intel-objects.json') 'Count'

    $highPrivilegeAssignments = $null; $sentinelRoleAssignments = $null
    if ($null -ne $rbac) {
        $highPrivilegeAssignments = @($rbac | Where-Object { (Get-MaturityPropertyValue $_ 'RoleDefinitionName' '') -in @('Owner', 'Contributor') }).Count
        $sentinelRoleAssignments = @(
            $rbac | Where-Object { ([string](Get-MaturityPropertyValue $_ 'RoleDefinitionName' '')) -like 'Microsoft Sentinel*' }
        ).Count
    }

    # The bookmarks list is refused when too large; the collector then keeps
    # the count the service reported in bookmarks-count.json.
    $bookmarks = Get-RowCount 'bookmarks.json'
    if ($null -eq $bookmarks) {
        $bookmarkCountDoc = Read-Json 'bookmarks-count.json'
        if ($null -ne $bookmarkCountDoc) { $bookmarks = [int](ConvertTo-MaturityNumber (Get-MaturityPropertyValue $bookmarkCountDoc 'Count' 0)) }
    }

    # Bookmarks created or changed within the run's window, from the API
    # list or the HuntingBookmark table's rows; $null when the evidence
    # cannot cover the window (Get-HuntingActivity.ps1).
    $activityRc = Read-Json 'run-context.json'
    $activityDays = 30
    $activityAsOf = [datetime]::UtcNow
    if ($activityRc -and $activityRc.PSObject.Properties['LookbackDays'] -and [int]$activityRc.LookbackDays -ge 1) {
        $activityDays = [int]$activityRc.LookbackDays
    }
    if ($activityRc -and $activityRc.PSObject.Properties['StartedAtUtc'] -and $activityRc.StartedAtUtc) {
        $parsedAsOf = [datetime]::MinValue
        if ($activityRc.StartedAtUtc -is [datetime]) { $activityAsOf = $activityRc.StartedAtUtc.ToUniversalTime() }
        elseif ([datetime]::TryParse([string]$activityRc.StartedAtUtc, [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$parsedAsOf)) {
            $activityAsOf = $parsedAsOf
        }
    }
    $huntingActivity = Get-HuntingActivity -Bookmarks (Read-Row 'bookmarks.json') -BookmarksCount (Read-Json 'bookmarks-count.json') -BookmarksFromLogs `
    (Read-Row 'bookmarks-from-logs.json') -Hunts (Read-Row 'hunts.json') -WorkspaceTables $schema -WindowDays $activityDays -AsOf $activityAsOf

    $connectorFailures7d = Get-RowSum -Rows $health -Property 'LogCount' -Filter {
        param($row) ((Get-MaturityPropertyValue $row 'Status' '') -eq 'Failure') -and
        (([string](Get-MaturityPropertyValue $row 'OperationName' '')) -match '(?i)data fetcher|data connector')
    }
    $sentinelHealthRows7d = Get-RowSum $health 'LogCount'
    $laQueryLogs7d = Get-RowSum (Read-Row 'la-query-logs.json') 'QueryCount'

    $metrics = [ordered]@{
        enabledRules              = $enabledRules
        customRules               = $customRules
        tacticsCovered            = $tacticsCovered
        dcrCount                  = Get-RowCount 'dcrs.json'
        laQueryLogs7d             = $laQueryLogs7d
        connectorFailures7d       = $connectorFailures7d
        sentinelHealthRows7d      = $sentinelHealthRows7d
        billableGb30d             = $billableGb30d
        entraTablesPresent        = $entraTablesPresent
        xdrTablesPresent          = $xdrTablesPresent
        mdcConnector              = Test-ConnectorKind @('AzureSecurityCenter')
        mdtiConnector             = Test-ConnectorKind @('MicrosoftThreatIntelligence', 'PremiumMicrosoftDefenderForThreatIntelligence')
        entityAnalyticsEnabled    = $entityAnalyticsEnabled
        playbooks                 = Get-RowCount 'playbooks.json'
        watchlists                = Get-RowCount 'watchlists.json'
        incidents30d              = $incidents30d
        closedIncidents30d        = $closedIncidents30d
        mttaMinutes               = $mttaMinutes
        searchOrRestoreJobs       = $searchOrRestoreJobs
        lakeExtendedTables        = $lakeExtendedTables
        tablesWithCustomRetention = $tablesWithCustomRetention
        summaryRules              = Get-RowCount 'summary-rules.json'
        tiIndicators30d           = $tiIndicators30d
        mdtiRows30d               = $mdtiRows30d
        tiObjects30d              = $tiObjects30d
        bookmarks                 = $bookmarks
        bookmarksRecent           = $huntingActivity.BookmarksRecent
        huntingQueries            = Get-RowCount 'hunting-queries.json'
        highPrivilegeAssignments  = $highPrivilegeAssignments
        sentinelRoleAssignments   = $sentinelRoleAssignments
    }
    return $metrics
}

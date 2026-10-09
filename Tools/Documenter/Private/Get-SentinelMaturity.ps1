#Requires -Version 7.2

<#
.SYNOPSIS
    Sentinel-As-Code maturity assessment. Scores a workspace 0 to 5 across
    eleven capability areas from the gap-engine outcomes and the _raw
    captures, and builds a prioritised roadmap to a target level.

.DESCRIPTION
    Pure data-in/data-out, testable end-to-end with fixture files.

    The criteria live in Resources/maturity-criteria.json. Each criterion
    names a source that resolves to one of three statuses:

        Met      the practice is in place or the coverage is present
        Gap      it is not
        Unknown  the input was not captured, so no judgement is made

    Source kinds:
        gapRule  a SENT rule outcome: Passed is Met, Fired is Gap, anything
                 else (Errored, Undefined, not evaluated) is Unknown
        metric   a value from New-MaturityMetrics compared with op/value;
                 a null metric (its file was not captured) is Unknown
        allOf    Gap if any source is Gap, else Unknown if any is Unknown,
                 else Met
        anyOf    Met if any source is Met, else Unknown if any is Unknown,
                 else Gap

    An area's score is 5 times the weight of its Met criteria over the
    weight of its Met and Gap criteria; Unknown never counts against a
    workspace. The level is the whole-number part of the score. Confidence
    reflects how many criteria could be evaluated. The overall score is the
    mean of the area scores.

    The roadmap lists every Gap criterion ordered by how much the overall
    score would rise if it were met, then by effort (Low first), then by
    id, with a running projected score. Quick wins are the first five
    Low-effort entries. The NIST CSF 2.0 rollup counts criteria per
    function and per referenced subcategory.

    Usage:
        $maturity = Get-SentinelMaturity -InputRoot './SecurityDocs/myws/_raw' `
                                         -ResourcesRoot './Tools/Documenter/Private/Resources' `
                                         -CriteriaPath './Tools/Documenter/Private/Resources/maturity-criteria.json' `
                                         -GapOutcomes $gapOutcomes -TargetLevel 3

    When -GapOutcomes is not supplied the engine reads gap-checks.json from
    InputRoot; when neither exists every gapRule criterion is Unknown.

.NOTES
    File:         Tools/Documenter/Private/Get-SentinelMaturity.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-09
    Version:      0.1.0
    Last Updated: 2026-10-09
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block. The criterion set and the
    roadmap idea come from the Sentinel health-check script contributed to
    this project; the scoring, the Unknown handling and the area taxonomy
    are this project's own.
#>

if (-not (Get-Command -Name Get-TableFamily -CommandType Function -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Get-TableFamily.ps1')
}

$script:MaturityEffortRank = @{ Low = 0; Medium = 1; High = 2 }

function Get-MaturityPropertyValue {
    <#
    .SYNOPSIS
        Read a dotted property path that may be absent, without tripping
        StrictMode. Hashtables and PSObjects both work.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)] [AllowNull()] $Object,
        [Parameter(Mandatory = $true)] [string] $Path,
        [Parameter(Mandatory = $false)] $Default = $null
    )
    if ($null -eq $Object) { return $Default }
    $current = $Object
    foreach ($segment in $Path -split '\.') {
        if ($null -eq $current) { return $Default }
        if ($current -is [System.Collections.IDictionary]) {
            if (-not $current.Contains($segment)) { return $Default }
            $current = $current[$segment]
        } else {
            # The indexer returns null for a missing member and never trips
            # StrictMode, which .Properties.Name does on an empty object.
            $prop = $current.PSObject.Properties[$segment]
            if ($null -eq $prop) { return $Default }
            $current = $prop.Value
        }
    }
    if ($null -eq $current) { return $Default }
    return $current
}

function Test-MaturityProperty {
    <#
    .SYNOPSIS
        True when the object carries the named member, even with a null
        value. Safe under StrictMode on empty objects and primitives.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false)] [AllowNull()] $Object,
        [Parameter(Mandatory = $true)] [string] $Name
    )
    if ($null -eq $Object) { return $false }
    if ($Object -is [System.Collections.IDictionary]) { return $Object.Contains($Name) }
    return ($null -ne $Object.PSObject.Properties[$Name])
}

function ConvertTo-MaturityNumber {
    <#
    .SYNOPSIS
        Parse a number that may arrive as a string (KQL cells) or a typed
        value (fixtures). Returns 0 when it cannot be parsed.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $false)] [AllowNull()] $Value)
    if ($null -eq $Value) { return 0.0 }
    if ($Value -is [bool]) { return $(if ($Value) { 1.0 } else { 0.0 }) }
    $d = 0.0
    if ([double]::TryParse([string]$Value, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { return $d }
    return 0.0
}

function New-MaturityMetrics {
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
    function Read-Rows([string]$Name) {
        $p = Join-Path $InputRoot $Name
        if (-not (Test-Path $p)) { return $null }
        $data = Read-Json $Name
        if ($null -eq $data) { return ,@() }
        return ,@($data | Where-Object { $null -ne $_ })
    }
    function Get-RowCount([string]$Name) {
        $rows = Read-Rows $Name
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

    $rules       = Read-Rows 'alert-rules.json'
    $connectors  = Read-Rows 'data-connectors-classic.json'
    $tables      = Read-Rows 'tables-with-data.json'
    $schema      = Read-Rows 'workspace-tables.json'
    $workspace   = Read-Json 'workspace.json'
    $settings    = Read-Json 'settings.json'
    $health      = Read-Rows 'sentinel-health-summary.json'
    $incidents   = Read-Rows 'incidents-summary.json'
    $mttr        = Read-Rows 'incidents-mttr.json'
    $tiCounts    = Read-Rows 'threat-intel-counts.json'
    $rbac        = Read-Rows 'rbac-workspace.json'
    $mitre       = $null
    $mitrePath   = Join-Path $ResourcesRoot 'mitre-attack.json'
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
            $tacticsCovered = @((Get-MaturityPropertyValue $mitre 'tactics') | Where-Object { $covered.Contains([string](Get-MaturityPropertyValue $_ 'sentinelShortName' '')) }).Count
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
            $ingested7d = if (Test-MaturityProperty $_ 'IngestedLast7d') { Get-MaturityPropertyValue $_ 'IngestedLast7d' 0 } else { Get-MaturityPropertyValue $_ 'BillableLast7d' 0 }
            ((Get-TableFamily -Table $name) -eq 'Entra ID / Identity') -and ((ConvertTo-MaturityNumber $ingested7d) -gt 0)
        }).Count
    }

    $xdr = Read-Rows 'xdr-table-presence.json'
    $xdrTablesPresent = if ($null -eq $xdr) { $null } else { @($xdr | Where-Object { (ConvertTo-MaturityNumber (Get-MaturityPropertyValue $_ 'RecordCount' 0)) -gt 0 }).Count }

    $entityAnalyticsEnabled = $null
    if ($null -ne $settings) {
        $providers = @(Get-MaturityPropertyValue $settings 'EntityAnalytics.properties.entityProviders' @() | Where-Object { $null -ne $_ })
        $entityAnalyticsEnabled = ($providers.Count -gt 0)
    }

    $incidents30d = $null; $closedIncidents30d = $null
    if ($null -ne $incidents) {
        if (@($incidents).Count -gt 0) {
            $incidents30d       = [int](ConvertTo-MaturityNumber (Get-MaturityPropertyValue $incidents[0] 'Count' 0))
            $closedIncidents30d = [int](ConvertTo-MaturityNumber (Get-MaturityPropertyValue $incidents[0] 'Closed' 0))
        } else { $incidents30d = 0; $closedIncidents30d = 0 }
    }
    $mttaMinutes = $null
    if ($null -ne $mttr -and @($mttr).Count -gt 0) {
        $raw = Get-MaturityPropertyValue $mttr[0] 'MTTAMinutes' $null
        if ($null -ne $raw) { $mttaMinutes = [math]::Round((ConvertTo-MaturityNumber $raw), 1) }
    }

    $searchJobs = Get-RowCount 'search-jobs.json'
    $restores   = Get-RowCount 'restore-logs.json'
    $searchOrRestoreJobs = if ($null -eq $searchJobs -and $null -eq $restores) { $null } else { [int]$searchJobs + [int]$restores }

    $lakeExtendedTables = $null; $tablesWithCustomRetention = $null
    if ($null -ne $schema) {
        $lakeExtendedTables = @($schema | Where-Object {
            $plan = [string](Get-MaturityPropertyValue $_ 'properties.plan' '')
            $interactive = ConvertTo-MaturityNumber (Get-MaturityPropertyValue $_ 'properties.retentionInDays' 0)
            $total = ConvertTo-MaturityNumber (Get-MaturityPropertyValue $_ 'properties.totalRetentionInDays' 0)
            ($plan -in @('DataLake', 'Auxiliary')) -or ($total -gt $interactive)
        }).Count
        $default = if ($null -ne $workspace) { ConvertTo-MaturityNumber (Get-MaturityPropertyValue $workspace 'properties.retentionInDays' $null) } else { $null }
        $tablesWithCustomRetention = @($schema | Where-Object {
            if (Test-MaturityProperty (Get-MaturityPropertyValue $_ 'properties' $null) 'retentionInDaysAsDefault') {
                -not [bool](Get-MaturityPropertyValue $_ 'properties.retentionInDaysAsDefault' $true)
            } elseif ($null -ne $default) {
                (ConvertTo-MaturityNumber (Get-MaturityPropertyValue $_ 'properties.retentionInDays' $default)) -ne $default
            } else { $false }
        }).Count
    }

    $tiIndicators30d = Get-RowSum $tiCounts 'Count'
    $mdtiRows30d     = Get-RowSum $tiCounts 'Count' { param($row) ([string](Get-MaturityPropertyValue $row 'SourceSystem' '')) -match '^Microsoft' }
    $tiObjects30d    = Get-RowSum (Read-Rows 'threat-intel-objects.json') 'Count'

    $highPrivilegeAssignments = $null; $sentinelRoleAssignments = $null
    if ($null -ne $rbac) {
        $highPrivilegeAssignments = @($rbac | Where-Object { (Get-MaturityPropertyValue $_ 'RoleDefinitionName' '') -in @('Owner', 'Contributor') }).Count
        $sentinelRoleAssignments  = @($rbac | Where-Object { ([string](Get-MaturityPropertyValue $_ 'RoleDefinitionName' '')) -like 'Microsoft Sentinel*' }).Count
    }

    $connectorFailures7d = Get-RowSum $health 'LogCount' { param($row) ((Get-MaturityPropertyValue $row 'Status' '') -eq 'Failure') -and (([string](Get-MaturityPropertyValue $row 'OperationName' '')) -match '(?i)data fetcher|data connector') }
    $sentinelHealthRows7d = Get-RowSum $health 'LogCount'
    $laQueryLogs7d = Get-RowSum (Read-Rows 'la-query-logs.json') 'QueryCount'

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
        bookmarks                 = Get-RowCount 'bookmarks.json'
        huntingQueries            = Get-RowCount 'hunting-queries.json'
        highPrivilegeAssignments  = $highPrivilegeAssignments
        sentinelRoleAssignments   = $sentinelRoleAssignments
    }
    return $metrics
}

function Test-MaturityCriteriaDocument {
    <#
    .SYNOPSIS
        Throw when the criteria document is malformed: duplicate or
        misnamed ids, unknown areas, metrics, CSF ids, levels or sources.

    .PARAMETER Document
        The parsed criteria document.

    .PARAMETER MetricNames
        The metric names New-MaturityMetrics produces.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] $Document,
        [Parameter(Mandatory = $true)] [string[]] $MetricNames
    )
    $problems = [System.Collections.Generic.List[string]]::new()
    $areaIds = @(Get-MaturityPropertyValue $Document 'areas' @() | ForEach-Object { [string](Get-MaturityPropertyValue $_ 'id' '') })
    if ($areaIds.Count -eq 0) { $problems.Add('no areas defined') }
    if (@($areaIds | Sort-Object -Unique).Count -ne $areaIds.Count) { $problems.Add('duplicate area ids') }
    $levels = @(Get-MaturityPropertyValue $Document 'levels' @() | ForEach-Object { [int](Get-MaturityPropertyValue $_ 'level' -1) } | Sort-Object)
    if (($levels -join ',') -ne '0,1,2,3,4,5') { $problems.Add("levels must be exactly 0 to 5 (found $($levels -join ','))") }
    $csfIds = @((Get-MaturityPropertyValue $Document 'csf.subcategories' @{}).PSObject.Properties.Name)
    $csfFunctions = @((Get-MaturityPropertyValue $Document 'csf.functions' @{}).PSObject.Properties.Name)
    foreach ($id in $csfIds) {
        if ($id -notmatch '^([A-Z]{2})\.[A-Z]{2}-\d{2}$' -or $Matches[1] -notin $csfFunctions) { $problems.Add("CSF id '$id' does not belong to a listed function") }
    }

    $seen = [System.Collections.Generic.HashSet[string]]::new()
    $criteria = @(Get-MaturityPropertyValue $Document 'criteria' @())
    if ($criteria.Count -eq 0) { $problems.Add('no criteria defined') }
    $checkSource = {
        param($Source, $Id)
        $kind = [string](Get-MaturityPropertyValue $Source 'kind' '')
        switch ($kind) {
            'gapRule' {
                if (([string](Get-MaturityPropertyValue $Source 'rule' '')) -notmatch '^SENT-\d{3,}$') { $problems.Add("$Id gapRule source needs a SENT rule id") }
            }
            'metric' {
                $path = [string](Get-MaturityPropertyValue $Source 'path' '')
                if ($path -notin $MetricNames) { $problems.Add("$Id references unknown metric '$path'") }
                if (([string](Get-MaturityPropertyValue $Source 'op' '')) -notin @('gt', 'ge', 'eq', 'lt', 'le')) { $problems.Add("$Id metric source has an unknown op") }
                if ($null -eq (Get-MaturityPropertyValue $Source 'value' $null)) { $problems.Add("$Id metric source has no value") }
            }
            { $_ -in 'allOf', 'anyOf' } {
                $inner = @(Get-MaturityPropertyValue $Source 'sources' @())
                if ($inner.Count -lt 2) { $problems.Add("$Id $kind needs at least two sources") }
                foreach ($s in $inner) { & $checkSource $s $Id }
            }
            default { $problems.Add("$Id has an unknown source kind '$kind'") }
        }
    }
    foreach ($c in $criteria) {
        $id = [string](Get-MaturityPropertyValue $c 'id' '')
        if ($id -notmatch '^SAC-[A-Z]+-\d{2}$') { $problems.Add("criterion id '$id' does not match SAC-<AREA>-NN") }
        if (-not $seen.Add($id)) { $problems.Add("duplicate criterion id '$id'") }
        $area = [string](Get-MaturityPropertyValue $c 'area' '')
        if ($area -notin $areaIds) { $problems.Add("$id names unknown area '$area'") }
        if ($id -notlike "SAC-$area-*") { $problems.Add("$id does not carry its area '$area' in the id") }
        if (([string](Get-MaturityPropertyValue $c 'kind' '')) -notin @('practice', 'coverage')) { $problems.Add("$id kind must be practice or coverage") }
        if ([string]::IsNullOrWhiteSpace([string](Get-MaturityPropertyValue $c 'name' ''))) { $problems.Add("$id has no name") }
        if ((ConvertTo-MaturityNumber (Get-MaturityPropertyValue $c 'weight' 0)) -le 0) { $problems.Add("$id weight must be positive") }
        if (([string](Get-MaturityPropertyValue $c 'effort' '')) -notin @('Low', 'Medium', 'High')) { $problems.Add("$id effort must be Low, Medium or High") }
        foreach ($ref in @(Get-MaturityPropertyValue $c 'csf' @())) {
            if ([string]$ref -notin $csfIds) { $problems.Add("$id references CSF subcategory '$ref' that is not in the reference") }
        }
        $source = Get-MaturityPropertyValue $c 'source' $null
        if ($null -eq $source) { $problems.Add("$id has no source") } else { & $checkSource $source $id }
        foreach ($text in @((Get-MaturityPropertyValue $c 'name' ''), (Get-MaturityPropertyValue $c 'impact' ''), (Get-MaturityPropertyValue $c 'guidance' ''))) {
            if ([string]$text -match [char]0x2014) { $problems.Add("$id text contains an em-dash") }
        }
    }
    if ($problems.Count -gt 0) {
        throw "maturity-criteria.json is invalid: $($problems -join '; ')"
    }
}

function Resolve-MaturitySource {
    <#
    .SYNOPSIS
        Resolve one source (recursively for allOf / anyOf) to Met, Gap or
        Unknown, with the metric value and the rule evidence that decided it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] $Source,
        [Parameter(Mandatory = $true)] $Metrics,
        [Parameter(Mandatory = $true)] [hashtable] $OutcomeById,
        [Parameter(Mandatory = $true)] [hashtable] $EvidenceById
    )
    $kind = [string](Get-MaturityPropertyValue $Source 'kind' '')
    switch ($kind) {
        'gapRule' {
            $rule = [string](Get-MaturityPropertyValue $Source 'rule' '')
            $outcome = if ($OutcomeById.ContainsKey($rule)) { $OutcomeById[$rule] } else { $null }
            $status = switch ($outcome) { 'Passed' { 'Met' } 'Fired' { 'Gap' } default { 'Unknown' } }
            $evidence = $null
            if ($status -eq 'Gap' -and $EvidenceById.ContainsKey($rule)) { $evidence = $EvidenceById[$rule] }
            elseif ($status -eq 'Unknown') { $evidence = "$rule was not evaluated in this run." }
            return [pscustomobject]@{ Status = $status; Metric = $null; Rule = $rule; Evidence = $evidence }
        }
        'metric' {
            $path = [string](Get-MaturityPropertyValue $Source 'path' '')
            $value = $Metrics[$path]
            if ($null -eq $value) { return [pscustomobject]@{ Status = 'Unknown'; Metric = $null; Rule = $null; Evidence = "Metric '$path' was not captured in this run." } }
            $expected = Get-MaturityPropertyValue $Source 'value' $null
            $op = [string](Get-MaturityPropertyValue $Source 'op' '')
            $pass = if ($expected -is [bool]) {
                ([bool]$value) -eq $expected
            } else {
                $left = ConvertTo-MaturityNumber $value; $right = ConvertTo-MaturityNumber $expected
                switch ($op) { 'gt' { $left -gt $right } 'ge' { $left -ge $right } 'eq' { $left -eq $right } 'lt' { $left -lt $right } 'le' { $left -le $right } default { $false } }
            }
            return [pscustomobject]@{ Status = $(if ($pass) { 'Met' } else { 'Gap' }); Metric = $value; Rule = $null; Evidence = $null }
        }
        { $_ -in 'allOf', 'anyOf' } {
            $parts = @(foreach ($s in @(Get-MaturityPropertyValue $Source 'sources' @())) { Resolve-MaturitySource -Source $s -Metrics $Metrics -OutcomeById $OutcomeById -EvidenceById $EvidenceById })
            $statuses = @($parts | ForEach-Object Status)
            $status = if ($kind -eq 'allOf') {
                if ($statuses -contains 'Gap') { 'Gap' } elseif ($statuses -contains 'Unknown') { 'Unknown' } else { 'Met' }
            } else {
                if ($statuses -contains 'Met') { 'Met' } elseif ($statuses -contains 'Unknown') { 'Unknown' } else { 'Gap' }
            }
            $decider = @($parts | Where-Object Status -eq $status | Select-Object -First 1)
            $metric = @($parts | Where-Object { $null -ne $_.Metric } | Select-Object -First 1 | ForEach-Object Metric)
            $evidence = @($parts | Where-Object { $_.Status -eq $status -and $_.Evidence } | ForEach-Object Evidence) -join ' '
            return [pscustomobject]@{
                Status   = $status
                Metric   = $(if ($metric.Count -gt 0) { $metric[0] } else { $null })
                Rule     = $(if ($decider.Count -gt 0) { $decider[0].Rule } else { $null })
                Evidence = $(if ($evidence) { $evidence } else { $null })
            }
        }
        default { throw "Unknown maturity source kind '$kind'." }
    }
}

function Format-MaturityEvidence {
    <#
    .SYNOPSIS
        Fill the {metric} token in an evidence template.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)] [AllowNull()] [AllowEmptyString()] [string] $Template,
        [Parameter(Mandatory = $false)] [AllowNull()] $Metric
    )
    if ([string]::IsNullOrWhiteSpace($Template)) { return $null }
    $text = if ($null -eq $Metric) { 'unknown' }
            elseif ($Metric -is [bool]) { $(if ($Metric) { 'yes' } else { 'no' }) }
            else {
                $n = ConvertTo-MaturityNumber $Metric
                if ($n -eq [math]::Floor($n)) { ([int64]$n).ToString('N0', [System.Globalization.CultureInfo]::InvariantCulture) } else { $n.ToString('0.0', [System.Globalization.CultureInfo]::InvariantCulture) }
            }
    return $Template.Replace('{metric}', $text)
}

function Get-SentinelMaturity {
    <#
    .SYNOPSIS
        Run the maturity assessment over a _raw folder.

    .PARAMETER InputRoot
        The _raw folder written by Export-SentinelInventory.ps1.

    .PARAMETER ResourcesRoot
        Tools/Documenter/Private/Resources.

    .PARAMETER CriteriaPath
        Path to maturity-criteria.json.

    .PARAMETER GapOutcomes
        The per-rule outcomes from Get-SentinelGap -OutcomeCollector. When
        omitted, gap-checks.json in InputRoot is read instead.

    .PARAMETER TargetLevel
        Level (1 to 5) the workspace is aiming for. Default 3.

    .OUTPUTS
        One [pscustomobject], the content of _raw/maturity.json.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)] [string] $InputRoot,
        [Parameter(Mandatory = $true)] [string] $ResourcesRoot,
        [Parameter(Mandatory = $true)] [string] $CriteriaPath,
        [Parameter(Mandatory = $false)] [AllowNull()] [object[]] $GapOutcomes,
        [Parameter(Mandatory = $false)] [ValidateRange(1, 5)] [int] $TargetLevel = 3
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    if (-not (Test-Path $InputRoot))     { throw "Input root not found: $InputRoot" }
    if (-not (Test-Path $ResourcesRoot)) { throw "Resources root not found: $ResourcesRoot" }
    if (-not (Test-Path $CriteriaPath))  { throw "Criteria file not found: $CriteriaPath" }

    $doc = Get-Content $CriteriaPath -Raw | ConvertFrom-Json -Depth 16
    $metrics = New-MaturityMetrics -InputRoot $InputRoot -ResourcesRoot $ResourcesRoot
    Test-MaturityCriteriaDocument -Document $doc -MetricNames @($metrics.Keys)

    # Rule outcomes: the collector passes them in; a standalone run reads the
    # file the gap engine wrote. Evidence for Gap criteria comes from the
    # findings file so the maturity page can quote it.
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

    $levelNames = @{}
    foreach ($l in @($doc.levels)) { $levelNames[[int]$l.level] = [string]$l.name }
    $confidenceGood = [int](Get-MaturityPropertyValue $doc 'confidence.good' 6)
    $confidenceModerate = [int](Get-MaturityPropertyValue $doc 'confidence.moderate' 4)

    # ----- criteria and areas -------------------------------------------
    $areas = @(foreach ($area in @($doc.areas)) {
        $areaId = [string]$area.id
        $resolved = @(foreach ($c in @($doc.criteria | Where-Object { [string]$_.area -eq $areaId })) {
            $r = Resolve-MaturitySource -Source $c.source -Metrics $metrics -OutcomeById $outcomeById -EvidenceById $evidenceById
            $template = switch ($r.Status) {
                'Met' { Get-MaturityPropertyValue $c 'evidence.met' $null }
                'Gap' { Get-MaturityPropertyValue $c 'evidence.gap' $null }
                default { $null }
            }
            $evidence = Format-MaturityEvidence -Template $template -Metric $r.Metric
            if (-not $evidence) { $evidence = $r.Evidence }
            if (-not $evidence) {
                $evidence = switch ($r.Status) {
                    'Met' { "$($r.Rule) passed." }
                    'Gap' { "$($r.Rule) fired." }
                    default { 'Not evaluated in this run.' }
                }
            }
            [pscustomobject]@{
                id       = [string]$c.id
                kind     = [string]$c.kind
                name     = [string]$c.name
                status   = $r.Status
                evidence = $evidence
                weight   = [double]$c.weight
                effort   = [string]$c.effort
                impact   = [string]$c.impact
                guidance = [string]$c.guidance
                csf      = @($c.csf | ForEach-Object { [string]$_ })
                source   = $c.source
                metric   = $r.Metric
                rule     = $r.Rule
            }
        })
        $known = @($resolved | Where-Object { $_.status -in 'Met', 'Gap' })
        # Measure-Object returns nothing for an empty input, so sum by hand.
        $sumKnown = 0.0; $sumMet = 0.0
        foreach ($k in $known) {
            $sumKnown += $k.weight
            if ($k.status -eq 'Met') { $sumMet += $k.weight }
        }
        $score = $null; $level = $null
        if ($known.Count -gt 0 -and $sumKnown -gt 0) {
            $score = [math]::Round(5.0 * [double]$sumMet / [double]$sumKnown, 2)
            $level = [int][math]::Floor($score)
        }
        $confidence = if ($known.Count -eq 0) { 'Not assessed' }
                      elseif ($known.Count -ge $confidenceGood) { 'Good' }
                      elseif ($known.Count -ge $confidenceModerate) { 'Moderate' }
                      else { 'Indicative' }
        [pscustomobject]@{
            id          = $areaId
            name        = [string]$area.name
            description = [string](Get-MaturityPropertyValue $area 'description' '')
            score       = $score
            level       = $level
            levelName   = $(if ($null -ne $level) { $levelNames[$level] } else { 'Not assessed' })
            met         = @($resolved | Where-Object status -eq 'Met').Count
            gap         = @($resolved | Where-Object status -eq 'Gap').Count
            unknown     = @($resolved | Where-Object status -eq 'Unknown').Count
            evaluated   = $known.Count
            confidence  = $confidence
            weightKnown = [double]$sumKnown
            criteria    = $resolved
        }
    })

    $assessed = @($areas | Where-Object { $null -ne $_.score })
    $overallScore = $null; $overallLevel = $null
    if ($assessed.Count -gt 0) {
        $overallScore = [math]::Round((($assessed | Measure-Object -Property score -Average).Average), 2)
        $overallLevel = [int][math]::Floor($overallScore)
    }

    # ----- roadmap ---------------------------------------------------------
    $roadmapRaw = @(foreach ($area in $assessed) {
        foreach ($c in @($area.criteria | Where-Object status -eq 'Gap')) {
            $areaLift = [math]::Round(5.0 * $c.weight / $area.weightKnown, 2)
            [pscustomobject]@{
                criterionId = $c.id
                area        = $area.id
                areaName    = $area.name
                name        = $c.name
                kind        = $c.kind
                evidence    = $c.evidence
                impact      = $c.impact
                guidance    = $c.guidance
                effort      = $c.effort
                csf         = $c.csf
                areaLift    = $areaLift
                overallLift = [math]::Round($areaLift / $assessed.Count, 3)
            }
        }
    })
    $ordered = @($roadmapRaw | Sort-Object -Property @{ Expression = 'overallLift'; Descending = $true }, @{ Expression = { $script:MaturityEffortRank[$_.effort] } }, @{ Expression = 'criterionId' })
    $running = if ($null -ne $overallScore) { [double]$overallScore } else { 0.0 }
    $priority = 0
    $roadmap = @(foreach ($entry in $ordered) {
        $priority++
        $running = [math]::Min(5.0, $running + $entry.overallLift)
        $entry | Add-Member -NotePropertyName priority -NotePropertyValue $priority -PassThru |
                 Add-Member -NotePropertyName projectedScore -NotePropertyValue ([math]::Round($running, 2)) -PassThru
    })
    $quickWins = @($roadmap | Where-Object effort -eq 'Low' | Select-Object -First 5)

    # ----- target ----------------------------------------------------------
    $below = @($assessed | Where-Object { $_.level -lt $TargetLevel } | ForEach-Object {
        [pscustomobject]@{ id = $_.id; name = $_.name; score = $_.score; level = $_.level; gapToTarget = [math]::Round($TargetLevel - $_.score, 2) }
    })

    # ----- NIST CSF rollup -------------------------------------------------
    $allCriteria = @($areas | ForEach-Object { $_.criteria })
    $functions = @(foreach ($fn in $doc.csf.functions.PSObject.Properties) {
        $hits = @($allCriteria | Where-Object { @($_.csf | Where-Object { $_ -like "$($fn.Name).*" }).Count -gt 0 })
        [pscustomobject]@{
            id       = $fn.Name
            name     = [string]$fn.Value
            criteria = $hits.Count
            met      = @($hits | Where-Object status -eq 'Met').Count
            gap      = @($hits | Where-Object status -eq 'Gap').Count
            unknown  = @($hits | Where-Object status -eq 'Unknown').Count
        }
    })
    $usedIds = @($allCriteria | ForEach-Object { $_.csf } | Sort-Object -Unique)
    $subcategories = @(foreach ($id in $usedIds) {
        $hits = @($allCriteria | Where-Object { $_.csf -contains $id })
        [pscustomobject]@{
            id          = $id
            function    = $id.Substring(0, 2)
            # Subcategory ids contain a dot, so read the member directly
            # rather than through the dotted-path helper.
            outcome     = [string]$doc.csf.subcategories.PSObject.Properties[$id].Value
            met         = @($hits | Where-Object status -eq 'Met').Count
            gap         = @($hits | Where-Object status -eq 'Gap').Count
            unknown     = @($hits | Where-Object status -eq 'Unknown').Count
            criteriaIds = @($hits | ForEach-Object id)
        }
    })

    return [pscustomobject]@{
        methodology      = [pscustomobject]@{
            name            = [string]$doc.methodology.name
            version         = [string]$doc.methodology.version
            criteriaVersion = [string]$doc.version
            scaleNote       = [string](Get-MaturityPropertyValue $doc 'methodology.scaleNote' '')
        }
        generatedAtUtc   = (Get-Date).ToUniversalTime().ToString('o')
        targetLevel      = $TargetLevel
        targetLevelName  = $levelNames[$TargetLevel]
        targetMet        = ($assessed.Count -gt 0 -and $below.Count -eq 0)
        areasBelowTarget = $below
        overall          = [pscustomobject]@{
            score     = $overallScore
            level     = $overallLevel
            levelName = $(if ($null -ne $overallLevel) { $levelNames[$overallLevel] } else { 'Not assessed' })
        }
        levels           = @($doc.levels | ForEach-Object { [pscustomobject]@{ level = [int]$_.level; name = [string]$_.name } })
        areas            = @($areas | ForEach-Object {
            [pscustomobject]@{
                id = $_.id; name = $_.name; description = $_.description; score = $_.score; level = $_.level; levelName = $_.levelName
                met = $_.met; gap = $_.gap; unknown = $_.unknown; evaluated = $_.evaluated; confidence = $_.confidence
                criteria = @($_.criteria | ForEach-Object {
                    [pscustomobject]@{ id = $_.id; kind = $_.kind; name = $_.name; status = $_.status; evidence = $_.evidence; weight = $_.weight; effort = $_.effort; impact = $_.impact; guidance = $_.guidance; csf = $_.csf; source = $_.source }
                })
            }
        })
        roadmap          = $roadmap
        quickWins        = $quickWins
        csf              = [pscustomobject]@{
            source        = [string](Get-MaturityPropertyValue $doc 'csf.source' '')
            functions     = $functions
            subcategories = $subcategories
        }
        outOfScope       = @(Get-MaturityPropertyValue $doc 'outOfScope' @())
        totals           = [pscustomobject]@{
            criteria = $allCriteria.Count
            met      = @($allCriteria | Where-Object status -eq 'Met').Count
            gap      = @($allCriteria | Where-Object status -eq 'Gap').Count
            unknown  = @($allCriteria | Where-Object status -eq 'Unknown').Count
        }
        metrics          = [pscustomobject]$metrics
    }
}

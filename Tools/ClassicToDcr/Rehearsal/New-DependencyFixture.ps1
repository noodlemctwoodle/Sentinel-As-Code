#Requires -Version 7.2
#Requires -Modules Az.Accounts, Az.OperationalInsights

<#
.SYNOPSIS
    Creates a known set of classic-table dependency chains in a Log Analytics
    workspace so an operator can prove that Invoke-TableMigrationReview.ps1
    finds them, including the indirect ones that run through a KQL parser.

.DESCRIPTION
    Invoke-TableMigrationReview.ps1 reports what content depends on a classic
    (_CL) table before that table is migrated. Direct references are easy: the
    rule names the table, so a word-boundary text match finds it. The dangerous
    case is indirect. An analytics rule queries a PARSER, and the parser queries
    the classic table. The rule never names the table, so migrating the table
    silently breaks a live detection and nothing in a direct-match report says
    so.

    This script manufactures those chains against real ARM responses, so the
    detection can be verified end to end rather than only against synthetic
    unit-test objects. It creates five scenarios plus one non-rule content type:

      Direct    {Prefix}Direct_CL  and a rule that queries the table by name.
      OneHop    {Prefix}OneHop_CL, a parser over it, and a rule that queries
                ONLY the parser.
      TwoHop    {Prefix}TwoHop_CL, an inner parser over it, an outer parser
                over the inner one, and a rule that queries ONLY the outer.
      Cycle     {Prefix}Cycle_CL and two parsers that reference each other,
                one of which also reads the table. Proves the resolver
                terminates instead of looping.
      Orphan    {Prefix}Orphan_CL with nothing pointing at it at all, so
                over-reporting is visible too.
      Hunt      a hunting query (a saved search in the 'Hunting Queries'
                category, no function alias) that reaches the OneHop table
                through the OneHop parser, so a non-rule content type is
                covered.

    A "parser" in Log Analytics is a saved search whose properties.functionAlias
    is set. Other queries invoke it by that alias exactly as if it were a table,
    which is what makes the indirect case invisible to a text match.

    SAFETY. This is designed to be survivable against a live security
    workspace, because that is where the dependency chains are worth proving:

      - Every object carries the -NamePrefix so it is unmistakably a fixture
        and trivially greppable.
      - Analytics rules are created DISABLED, at Informational severity, with
        incident creation off, and with their query clamped by '| where 1 == 0'
        so they return no rows even if somebody enables them by hand. Enabling
        them needs an explicit switch; removing the clamp needs a second one.
      - A function alias that collides with a real table name would shadow that
        table for EVERY query in the workspace and silently rewrite live
        detections. The script refuses to create such an alias, checking the
        live workspace table list, the bundled solution mapping and a static
        floor list before it writes anything.
      - Preflight aborts the whole run if any target name already exists and
        does not carry this script's ownership marker. Nothing is overwritten.
      - Ingested volume is a handful of records per table. Ingestion is
        billable and cannot be recalled.
      - Every write and every delete runs behind ShouldProcess.

    ORDERING. Saved searches are not validated server side, but analytics rules
    are: a rule PUT whose query names a table or function that does not resolve
    comes back HTTP 400 "Failed to resolve table or column expression named".
    So the run goes tables, then a wait for the table to become queryable, then
    parsers, then the hunting query, then the rules last. Teardown is the
    reverse. Allow ten to twenty minutes for a cold run; the time goes on first
    ingestion latency, not on the ARM calls.

    REMOVAL. -Remove enumerates the workspace and deletes only objects that
    carry the ownership marker. A table whose subtype is still Classic cannot
    be deleted through the Tables API; -Remove reports that and stops rather
    than surfacing a raw ARM error. -MigrateBeforeRemove migrates it (one-way)
    and then deletes it.

.PARAMETER ResourceGroupName
    Resource group containing the Log Analytics workspace.

.PARAMETER WorkspaceName
    Log Analytics workspace name.

.PARAMETER SubscriptionId
    Subscription to operate in. Defaults to the current Az context.

.PARAMETER NamePrefix
    Shared prefix stamped on every object the script creates, so the fixture is
    obvious in a portal list and greppable in a report. Defaults to 'SacDep'.
    Must start with a letter and be 3 to 16 characters, so it cannot be blanked
    into a prefix that matches everything.

.PARAMETER Scenario
    Which scenarios to create or remove. Defaults to all of them. Selecting
    'Hunt' implies 'OneHop', because the hunting query reaches its table
    through the OneHop parser. Use this to skip 'Cycle' if you would rather
    not leave a deliberately unresolvable parser pair in the workspace.

.PARAMETER RecordCount
    Records posted per fixture table. Defaults to 5. The fixture proves
    dependency wiring, not data volume, and ingestion is billable.

.PARAMETER OdsEndpointSuffix
    Ingestion endpoint suffix for the HTTP Data Collector API. Defaults to the
    public cloud value 'ods.opinsights.azure.com'. For Azure Government use
    'ods.opinsights.azure.us'.

.PARAMETER TimeoutSeconds
    Budget for waiting on each new table: first for the table resource to
    appear through the Tables API, then for it to become queryable, which is
    the gate the analytics rule validator actually cares about. Defaults to
    900.

.PARAMETER EnableRules
    Create the analytics rules ENABLED. Off by default and deliberately awkward
    to reach. The zero-row clamp stays on the query, so the rules still cannot
    produce an alert. Warns before it writes.

.PARAMETER EnableRulesWithLiveQuery
    Used with -EnableRules. Also removes the zero-row clamp, so the rules run
    a real query against production data. This is the only combination that can
    produce an alert. Incident creation stays off.

.PARAMETER Remove
    Delete the fixture instead of creating it. Enumerates the workspace and
    deletes only objects carrying this script's ownership marker; anything that
    merely matches the prefix is reported and left alone.

.PARAMETER MigrateBeforeRemove
    Used with -Remove. If a fixture table is still Classic, migrate it to
    DCR-based (one-way) so it becomes deletable, then delete it. Ownership is
    proved before the migration, never after.

.PARAMETER RemoveUnmarkedTable
    Used with -Remove. Deletes a table whose name matches the fixture set but
    which carries no ownership marker column. This is the escape hatch for a
    run that was interrupted before the marker landed in the schema. It can
    delete somebody else's table, so it warns loudly and is never implied by
    any other switch.

.PARAMETER Reseed
    Post records again to a table that already exists and is already marked.
    Without this the seed is skipped, because re-posting is billable and buys
    nothing.

.EXAMPLE
    ./Tools/ClassicToDcr/Rehearsal/New-DependencyFixture.ps1 `
        -ResourceGroupName rg-sentinel -WorkspaceName ws-sentinel -WhatIf

    Runs the read-only preflight, prints the full plan with one line per
    object, and creates nothing. Run this first, every time.

.EXAMPLE
    ./Tools/ClassicToDcr/Rehearsal/New-DependencyFixture.ps1 `
        -ResourceGroupName rg-sentinel -WorkspaceName ws-sentinel -Confirm:$false

    Creates the whole fixture set: five classic tables, five parsers, one
    hunting query and four disabled analytics rules.

.EXAMPLE
    ./Tools/ClassicToDcr/Rehearsal/New-DependencyFixture.ps1 `
        -ResourceGroupName rg-sentinel -WorkspaceName ws-sentinel `
        -Scenario OneHop, TwoHop, Hunt -Confirm:$false

    Creates only the indirect chains, skipping the deliberately unresolvable
    cycle pair.

.EXAMPLE
    ./Tools/ClassicToDcr/Rehearsal/New-DependencyFixture.ps1 `
        -ResourceGroupName rg-sentinel -WorkspaceName ws-sentinel -Remove -WhatIf

    Lists exactly which resource ids would be deleted and which marker
    qualified each one. Deleting an analytics rule is instant and has no
    soft-delete, so this dry run is the only undo.

.EXAMPLE
    ./Tools/ClassicToDcr/Rehearsal/New-DependencyFixture.ps1 `
        -ResourceGroupName rg-sentinel -WorkspaceName ws-sentinel `
        -Remove -MigrateBeforeRemove -Confirm:$false

    Removes the fixture, migrating any table still stuck on Classic so the
    Tables API will accept the delete.

.NOTES
    File:         Tools/ClassicToDcr/Rehearsal/New-DependencyFixture.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Created:      2026-07-28
    Version:      1.0.1
    Last Updated: 2026-09-01
    Website:      https://sentinel.blog
    Requires:     PowerShell 7.2+, Az.Accounts, Az.OperationalInsights

    Runs standalone. Nothing from this repository needs to be alongside it. The
    bundled data/solution-mapping.json is used for the alias guard when it is
    present, and the script falls back to a static list with a warning when it
    is not.

    Required RBAC:
      - Log Analytics Contributor on the workspace (read shared keys, create
        and delete saved searches, migrate and delete tables)
      - Microsoft Sentinel Contributor on the workspace (create and delete
        analytics rules)

    ConfirmImpact is High, so an interactive session prompts for every object.
    Pass -Confirm:$false for a scripted or pipeline run.

    Known consequences worth reading before the first run:

      - The cyclic parser pair created by the Cycle scenario is permanently
        unresolvable at query time. That is the point (it proves the resolver
        terminates), but the pair will fail any live query and will look broken
        in the portal function list. Skip it with -Scenario if that is not
        acceptable. No analytics rule points at a cycle member, because the
        server-side query validator would reject such a rule outright.

      - A drift detector that absorbs unmanaged workspace rules into source
        control will pick up the fixture rules if they are left in place when
        it runs. Complete create, review and teardown inside one working
        window, or exclude the prefix on the drift run. The
        '[SacFixture:...]' sentinel in each rule description makes anything
        absorbed easy to find.

      - The HTTP Data Collector API retires on 2026-09-14. After that date this
        script cannot create classic tables, because nothing can.

    Reference:
      https://learn.microsoft.com/azure/azure-monitor/logs/data-collector-api
      https://learn.microsoft.com/azure/azure-monitor/logs/functions
      https://learn.microsoft.com/rest/api/securityinsights/alert-rules/create-or-update
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param (
    [Parameter(Mandatory)]
    [string] $ResourceGroupName

  , [Parameter(Mandatory)]
    [string] $WorkspaceName

  , [Parameter()]
    [string] $SubscriptionId

  , [Parameter()]
    [ValidatePattern('^[A-Za-z][A-Za-z0-9]{2,15}$')]
    [string] $NamePrefix = 'SacDep'

  , [Parameter()]
    [ValidateSet('Direct', 'OneHop', 'TwoHop', 'Cycle', 'Orphan', 'Hunt')]
    [string[]] $Scenario

  , [Parameter()]
    [ValidateRange(1, 100)]
    [int] $RecordCount = 5

  , [Parameter()]
    [string] $OdsEndpointSuffix = 'ods.opinsights.azure.com'

  , [Parameter()]
    [ValidateRange(60, 3600)]
    [int] $TimeoutSeconds = 900

  , [Parameter()]
    [switch] $EnableRules

  , [Parameter()]
    [switch] $EnableRulesWithLiveQuery

  , [Parameter()]
    [switch] $Remove

  , [Parameter()]
    [switch] $MigrateBeforeRemove

  , [Parameter()]
    [switch] $RemoveUnmarkedTable

  , [Parameter()]
    [switch] $Reseed
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region -- Logging ------------------------------------------------------------

# Self-contained by design. This kit deliberately does NOT import the repo's
# Sentinel.Common module: it must run unchanged on a jump box or in an
# automation account where that module is absent. Write-PipelineMessage is
# defined locally to mirror Sentinel.Common's behaviour.

function Write-PipelineMessage {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Console output is the point; mirrors Sentinel.Common.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Message
        ,
        [Parameter(Mandatory = $false)]
        [ValidateSet('Info', 'Warning', 'Error', 'Section', 'Success', 'Debug')]
        [string]$Level = 'Info'
    )

    $isAdo = $null -ne $env:BUILD_BUILDID

    switch ($Level) {
        'Info'    { Write-Host $Message }
        'Warning' {
            if ($isAdo) { Write-Host "##[warning]$Message" } else { Write-Warning $Message }
        }
        'Error'   {
            if ($isAdo) { Write-Host "##[error]$Message" } else { Write-Error $Message -ErrorAction Continue }
        }
        'Section' {
            if ($isAdo) { Write-Host "##[section]$Message" } else { Write-Host "`n$Message" -ForegroundColor Cyan }
        }
        'Success' {
            if ($isAdo) { Write-Host $Message } else { Write-Host $Message -ForegroundColor Green }
        }
        'Debug'   { Write-Verbose $Message }
    }
}

#endregion

#region -- Constants -----------------------------------------------------------

$script:TablesApiVersion        = '2023-09-01'
$script:SentinelApiVersion      = '2024-03-01'
$script:SavedSearchApiVersion   = '2020-08-01'
$script:DataCollectorApiVersion = '2016-04-01'

# Ownership marker. Constant across prefixes on purpose: the prefix says which
# fixture run an object belongs to, the marker says the object is a fixture at
# all. Prefix match alone is never enough to justify a delete.
$script:FixtureMarker    = 'ClassicToDcr-DependencyFixture'
$script:FixtureTagName   = 'SacFixture'
$script:FixtureRunTag    = 'SacFixtureRun'
$script:FixtureScenTag   = 'SacFixtureScenario'

# Ingested field that becomes the marker column the Tables API reports back.
# Tables carry no ARM tags and a classic table is created implicitly by the
# Data Collector API, so the only place a marker can live is the data.
$script:MarkerFieldName  = 'SacFixtureMarker'
$script:MarkerColumnName = 'SacFixtureMarker_s'

# Namespace folded into the deterministic rule GUIDs, so ownership of an
# analytics rule is recomputable rather than merely pattern matched.
$script:RuleIdNamespace  = 'Sentinel-As-Code/ClassicToDcr/DependencyFixture'

# Appended to every fixture rule query. Guarantees zero rows, which means the
# GreaterThan 0 trigger can never be satisfied even if somebody enables the
# rule by hand. The table name and the parser alias stay textually present, so
# the review tool still sees exactly what it is meant to see.
$script:QueryClamp = '| where 1 == 0'

$script:ScenarioOrder = @('Direct', 'OneHop', 'TwoHop', 'Cycle', 'Orphan', 'Hunt')

# Bundled solution mapping, used to widen the reserved-name list when present.
$script:MappingPath = Join-Path $PSScriptRoot '..' 'data' 'solution-mapping.json'

# Static floor for the alias guard. The live workspace table list is the real
# check; this exists so the guard still refuses the obvious catastrophes when
# the bundled mapping is missing and the workspace list is thin.
$script:ReservedTableFloor = @(
    'Alert', 'AlertEvidence', 'AlertInfo', 'AuditLogs', 'AzureActivity',
    'AzureDiagnostics', 'AzureMetrics', 'AADNonInteractiveUserSignInLogs',
    'AADServicePrincipalSignInLogs', 'CloudAppEvents', 'CommonSecurityLog',
    'ConfigurationData', 'ContainerLog', 'DeviceEvents', 'DeviceFileEvents',
    'DeviceImageLoadEvents', 'DeviceInfo', 'DeviceLogonEvents',
    'DeviceNetworkEvents', 'DeviceNetworkInfo', 'DeviceProcessEvents',
    'DeviceRegistryEvents', 'DeviceTvmSoftwareVulnerabilities', 'DnsEvents',
    'DnsInventory', 'EmailAttachmentInfo', 'EmailEvents',
    'EmailPostDeliveryEvents', 'EmailUrlInfo', 'Event', 'Heartbeat',
    'IdentityDirectoryEvents', 'IdentityInfo', 'IdentityLogonEvents',
    'IdentityQueryEvents', 'InsightsMetrics', 'KubeEvents', 'KubePodInventory',
    'LAQueryLogs', 'OfficeActivity', 'Operation', 'Perf', 'ProtectionStatus',
    'SecurityAlert', 'SecurityBaseline', 'SecurityEvent', 'SecurityIncident',
    'SentinelAudit', 'SentinelHealth', 'SigninLogs', 'Syslog',
    'ThreatIntelligenceIndicator', 'Update', 'UpdateSummary', 'Usage',
    'UrlClickEvents', 'W3CIISLog', 'Watchlist', 'WindowsEvent',
    'WindowsFirewall'
)

#endregion

#region -- Data Collector helpers ---------------------------------------------

function New-DataCollectorSignature {
    <#
    .SYNOPSIS
        Builds the SharedKey Authorization header value for the Data
        Collector API.

    .DESCRIPTION
        Signs the documented string-to-hash with HMAC-SHA256 using the
        base64-decoded workspace shared key.

        ContentLength must be the UTF-8 BYTE length of the request body, not
        its character length. Passing the character length is the classic
        cause of a 403 signature mismatch on any body containing multi-byte
        characters, so the caller computes it from the encoded bytes and the
        two must agree.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure function: computes a signature string, changes no state.')]
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)] [string] $WorkspaceId
      , [Parameter(Mandatory)] [string] $SharedKey
      , [Parameter(Mandatory)] [int]    $ContentLength
      , [Parameter(Mandatory)] [string] $Rfc1123Date
      , [Parameter()]          [string] $Method      = 'POST'
      , [Parameter()]          [string] $ContentType = 'application/json'
      , [Parameter()]          [string] $Resource    = '/api/logs'
    )

    $xHeaders     = "x-ms-date:$Rfc1123Date"
    $stringToHash = "$Method`n$ContentLength`n$ContentType`n$xHeaders`n$Resource"

    $bytesToHash = [System.Text.Encoding]::UTF8.GetBytes($stringToHash)
    $keyBytes    = [System.Convert]::FromBase64String($SharedKey)

    $hmac = [System.Security.Cryptography.HMACSHA256]::new($keyBytes)
    try {
        $hash    = $hmac.ComputeHash($bytesToHash)
        $encoded = [System.Convert]::ToBase64String($hash)
    }
    finally {
        $hmac.Dispose()
    }

    return "SharedKey ${WorkspaceId}:${encoded}"
}

function New-DependencyFixtureRecord {
    <#
    .SYNOPSIS
        Generates the small batch of records that brings one fixture table
        into existence.

    .DESCRIPTION
        The Data Collector API creates the table implicitly from the first
        POST, inferring a column type per field and appending a suffix
        (string -> _s). The batch is deliberately tiny: the fixture proves
        dependency wiring, not data volume, and ingestion is billable and
        cannot be recalled.

        Every record carries the marker field, which becomes the
        SacFixtureMarker_s column. That column is the only ownership evidence
        a table can hold, and it is readable from the Tables API without any
        data-plane query, so -Remove can prove ownership cheaply.

    .PARAMETER Count
        Number of records to generate.

    .PARAMETER ReferenceTime
        UTC base time. Records are spread backwards from it. Injected so the
        generator is deterministic under test.

    .PARAMETER Marker
        Ownership marker value written into every record.

    .PARAMETER ScenarioName
        Scenario the table belongs to, carried through for readability when
        somebody looks at the rows in the portal.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure function: builds in-memory records, changes no state.')]
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.List[hashtable]])]
    param (
        [Parameter(Mandatory)] [int]      $Count
      , [Parameter(Mandatory)] [datetime] $ReferenceTime
      , [Parameter(Mandatory)] [string]   $Marker
      , [Parameter(Mandatory)] [string]   $ScenarioName
    )

    $sourceHost = 'fixture-01', 'fixture-02', 'fixture-03'
    $severity   = 'Information', 'Warning'
    $records    = [System.Collections.Generic.List[hashtable]]::new()

    for ($i = 0; $i -lt $Count; $i++) {
        $records.Add(@{
            # Nominated as time-generated-field, becomes TimeGenerated.
            Timestamp                 = $ReferenceTime.AddSeconds(-1 * $i).ToString('o')
            SourceHost                = $sourceHost[$i % $sourceHost.Count]
            Severity                  = $severity[$i % $severity.Count]
            Scenario                  = $ScenarioName
            Message                   = "Dependency fixture record $i for scenario $ScenarioName."
            $script:MarkerFieldName   = $Marker
        })
    }

    return $records
}

function Send-DataCollectorBatch {
    <#
    .SYNOPSIS
        Signs and posts one batch to the HTTP Data Collector API.

    .DESCRIPTION
        The x-ms-date and the content length are part of the signed string, so
        the signature is recomputed on every call rather than reused.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]   $IngestUri
      , [Parameter(Mandatory)] [string]   $WorkspaceId
      , [Parameter(Mandatory)] [string]   $SharedKey
      , [Parameter(Mandatory)] [string]   $LogType
      , [Parameter(Mandatory)] [object[]] $Record
      , [Parameter()]          [string]   $TimeField = 'Timestamp'
    )

    $body      = ConvertTo-Json -InputObject @($Record) -Depth 5
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
    $rfc1123   = [datetime]::UtcNow.ToString('r')

    $signature = New-DataCollectorSignature -WorkspaceId $WorkspaceId -SharedKey $SharedKey `
                                            -ContentLength $bodyBytes.Length -Rfc1123Date $rfc1123

    $headers = @{
        'Authorization'        = $signature
        'Log-Type'             = $LogType
        'x-ms-date'            = $rfc1123
        'time-generated-field' = $TimeField
    }

    Invoke-RestMethod -Uri $IngestUri -Method Post -ContentType 'application/json' `
                      -Headers $headers -Body $bodyBytes | Out-Null
}

#endregion

#region -- ARM helpers ---------------------------------------------------------

function Invoke-ArmRequest {
    <#
    .SYNOPSIS
        Invoke-AzRestMethod wrapper that routes relative paths to -Path and
        absolute URLs to -Uri, so sovereign clouds work without a hardcoded
        host, and that carries a request body when one is supplied.

    .DESCRIPTION
        The sibling rehearsal scripts only ever GET or DELETE, so their copies
        of this helper take no payload. This fixture has to PUT saved searches
        and analytics rules, hence -Payload.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string] $Uri
      , [Parameter()]          [string] $Method = 'GET'
      , [Parameter()]          [string] $Payload
      , [Parameter()]          [int[]]  $SuccessCode = @(200, 201, 202, 204)
    )

    $splat = @{ Method = $Method }

    if ([System.Uri]::IsWellFormedUriString($Uri, [System.UriKind]::Absolute)) {
        $splat['Uri'] = $Uri
    }
    else {
        $splat['Path'] = $Uri
    }

    if (-not [string]::IsNullOrWhiteSpace($Payload)) {
        $splat['Payload'] = $Payload
    }

    $response = Invoke-AzRestMethod @splat

    if ($response.StatusCode -notin $SuccessCode) {
        throw "ARM request failed [$Method $Uri]: HTTP $($response.StatusCode) $($response.Content)"
    }

    return $response
}

function Get-ArmCollection {
    <#
    .SYNOPSIS
        GETs an ARM list endpoint and returns the 'value' array, following
        nextLink so a paged workspace does not silently truncate the guard.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param (
        [Parameter(Mandatory)] [string] $Uri
    )

    $items = [System.Collections.Generic.List[object]]::new()
    $next  = $Uri

    while ($next) {
        $response = Invoke-ArmRequest -Uri $next -Method GET -SuccessCode @(200)
        $parsed   = $response.Content | ConvertFrom-Json

        $valueProp = $parsed.PSObject.Properties['value']
        if ($valueProp -and $valueProp.Value) {
            foreach ($item in @($valueProp.Value)) { $items.Add($item) }
        }

        $nextProp = $parsed.PSObject.Properties['nextLink']
        $next     = if ($nextProp -and $nextProp.Value) { [string]$nextProp.Value } else { $null }
    }

    return $items.ToArray()
}

#endregion

#region -- Naming and scenario construction ------------------------------------

function Resolve-FixtureScenario {
    <#
    .SYNOPSIS
        Normalises the requested scenario list.

    .DESCRIPTION
        An empty selection means all of them. 'Hunt' implies 'OneHop', because
        the hunting query reaches its table through the OneHop parser and would
        otherwise reference an alias that does not exist. The result is always
        returned in the canonical create order, which is also the order the
        plan banner prints.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param (
        [Parameter()] [AllowEmptyCollection()] [AllowNull()] [string[]] $Scenario
    )

    if (-not $Scenario -or $Scenario.Count -eq 0) {
        return $script:ScenarioOrder
    }

    $selected = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase)

    foreach ($name in $Scenario) {
        if (-not [string]::IsNullOrWhiteSpace($name)) { [void]$selected.Add($name.Trim()) }
    }

    if ($selected.Contains('Hunt')) { [void]$selected.Add('OneHop') }

    return @($script:ScenarioOrder | Where-Object { $selected.Contains($_) })
}

function New-FixtureRuleId {
    <#
    .SYNOPSIS
        Derives the analytics rule resource name deterministically from the
        prefix and the scenario.

    .DESCRIPTION
        The {ruleId} URL segment is caller chosen. Deriving it means a re-run
        converges on the same rule rather than littering the workspace with
        duplicates, and it means -Remove can RECOMPUTE which rules are ours
        instead of trusting a display name that somebody may have edited.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure function: derives a name, changes no state.')]
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)] [string] $NamePrefix
      , [Parameter(Mandatory)] [string] $ScenarioName
    )

    $seed = "$script:RuleIdNamespace|$NamePrefix|$ScenarioName"

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($seed))
    }
    finally {
        $sha.Dispose()
    }

    return ([guid]::new([byte[]]$hash[0..15])).ToString()
}

function Get-FixtureNamingPlan {
    <#
    .SYNOPSIS
        Builds the complete object graph the fixture will create: table names,
        parser ids and aliases, the hunting query, and the analytics rules,
        with the KQL for each.

    .DESCRIPTION
        Everything downstream reads from this one structure, so the plan
        banner, the create path, the removal path and the tests all agree on
        what the fixture is by construction rather than by convention.

        Two rules about the KQL in here are load bearing:

          - An INDIRECT query must not contain the literal table name
            anywhere, comments included. The review tool matches on text, so a
            table name in a comment would make the fixture quietly prove the
            wrong thing.

          - No analytics rule may query a cycle member. Sentinel validates a
            rule's KQL server side against the workspace schema, and the cycle
            pair never resolves, so such a rule comes back HTTP 400. The Cycle
            rule therefore names the table directly. Resolution is still
            exercised: walking the table's dependents reaches CycleA, which
            reaches CycleB, which reaches CycleA again.

    .PARAMETER NamePrefix
        Shared prefix for every object.

    .PARAMETER ScenarioName
        Scenarios to include. Defaults to all of them.

    .PARAMETER QueryClamp
        Line appended to every analytics rule query. Pass an empty string to
        author the rules without the zero-row clamp.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure function: builds an in-memory plan, changes no state.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)] [string]   $NamePrefix
      , [Parameter()] [AllowEmptyCollection()] [AllowNull()] [string[]] $ScenarioName
      , [Parameter()] [AllowEmptyString()]     [string]      $QueryClamp = $script:QueryClamp
    )

    $wanted = Resolve-FixtureScenario -Scenario $ScenarioName

    $tableFor = {
        param([string]$Suffix)
        "${NamePrefix}${Suffix}_CL"
    }

    $oneHopTable  = & $tableFor 'OneHop'
    $twoHopTable  = & $tableFor 'TwoHop'
    $cycleTable   = & $tableFor 'Cycle'
    $directTable  = & $tableFor 'Direct'
    $orphanTable  = & $tableFor 'Orphan'

    $aliasOneHop  = "${NamePrefix}OneHopParser"
    $aliasInner   = "${NamePrefix}InnerParser"
    $aliasOuter   = "${NamePrefix}OuterParser"
    $aliasCycleA  = "${NamePrefix}CycleA"
    $aliasCycleB  = "${NamePrefix}CycleB"

    $projection   = "| project TimeGenerated, SourceHost_s, Severity_s, $script:MarkerColumnName"

    $allTable = @(
        [pscustomobject]@{ ScenarioName = 'Direct'; LogType = "${NamePrefix}Direct"; TableName = $directTable }
        [pscustomobject]@{ ScenarioName = 'OneHop'; LogType = "${NamePrefix}OneHop"; TableName = $oneHopTable }
        [pscustomobject]@{ ScenarioName = 'TwoHop'; LogType = "${NamePrefix}TwoHop"; TableName = $twoHopTable }
        [pscustomobject]@{ ScenarioName = 'Cycle';  LogType = "${NamePrefix}Cycle";  TableName = $cycleTable }
        [pscustomobject]@{ ScenarioName = 'Orphan'; LogType = "${NamePrefix}Orphan"; TableName = $orphanTable }
    )

    # Parsers are authored in dependency order so a partial failure never
    # leaves an outer parser pointing at an alias that does not exist yet.
    # The cycle needs three writes: a genuinely cyclic pair cannot be created
    # in two without one of them momentarily dangling.
    $allParser = @(
        [pscustomobject]@{
            ScenarioName  = 'OneHop'
            SavedSearchId = "${NamePrefix}-OneHopParser"
            Alias         = $aliasOneHop
            DisplayName   = "$NamePrefix fixture one-hop parser"
            Query         = "$oneHopTable`n$projection"
            Order         = 1
            IsCycleClosure = $false
        }
        [pscustomobject]@{
            ScenarioName  = 'TwoHop'
            SavedSearchId = "${NamePrefix}-InnerParser"
            Alias         = $aliasInner
            DisplayName   = "$NamePrefix fixture inner parser"
            Query         = "$twoHopTable`n$projection"
            Order         = 2
            IsCycleClosure = $false
        }
        [pscustomobject]@{
            ScenarioName  = 'TwoHop'
            SavedSearchId = "${NamePrefix}-OuterParser"
            Alias         = $aliasOuter
            DisplayName   = "$NamePrefix fixture outer parser"
            Query         = "$aliasInner`n| where isnotempty(SourceHost_s)"
            Order         = 3
            IsCycleClosure = $false
        }
        [pscustomobject]@{
            ScenarioName  = 'Cycle'
            SavedSearchId = "${NamePrefix}-CycleA"
            Alias         = $aliasCycleA
            DisplayName   = "$NamePrefix fixture cycle parser A"
            Query         = "$cycleTable`n$projection"
            Order         = 4
            IsCycleClosure = $false
        }
        [pscustomobject]@{
            ScenarioName  = 'Cycle'
            SavedSearchId = "${NamePrefix}-CycleB"
            Alias         = $aliasCycleB
            DisplayName   = "$NamePrefix fixture cycle parser B"
            Query         = "$aliasCycleA`n| where isnotempty(SourceHost_s)"
            Order         = 5
            IsCycleClosure = $false
        }
        [pscustomobject]@{
            ScenarioName  = 'Cycle'
            SavedSearchId = "${NamePrefix}-CycleA"
            Alias         = $aliasCycleA
            DisplayName   = "$NamePrefix fixture cycle parser A"
            Query         = "union $cycleTable, $aliasCycleB`n| project TimeGenerated, SourceHost_s"
            Order         = 6
            IsCycleClosure = $true
        }
    )

    $allHunt = @(
        [pscustomobject]@{
            ScenarioName  = 'Hunt'
            SavedSearchId = "${NamePrefix}-Hunt"
            DisplayName   = "$NamePrefix fixture hunting query via parser"
            Query         = "$aliasOneHop`n| summarize Hits = count() by SourceHost_s"
        }
    )

    $clampLine = if ([string]::IsNullOrWhiteSpace($QueryClamp)) { '' } else { "`n$QueryClamp" }

    $allRule = @(
        [pscustomobject]@{
            ScenarioName = 'Direct'
            DisplayName  = "$NamePrefix fixture - direct table reference"
            Query        = "$directTable$clampLine"
            IsIndirect   = $false
        }
        [pscustomobject]@{
            ScenarioName = 'OneHop'
            DisplayName  = "$NamePrefix fixture - one hop through a parser"
            Query        = "$aliasOneHop$clampLine"
            IsIndirect   = $true
        }
        [pscustomobject]@{
            ScenarioName = 'TwoHop'
            DisplayName  = "$NamePrefix fixture - two hops through parsers"
            Query        = "$aliasOuter$clampLine"
            IsIndirect   = $true
        }
        [pscustomobject]@{
            # Deliberately direct. A rule naming a cycle member would be
            # rejected by the server-side query validator, because the pair
            # never resolves.
            ScenarioName = 'Cycle'
            DisplayName  = "$NamePrefix fixture - table also read by a cyclic parser pair"
            Query        = "$cycleTable$clampLine"
            IsIndirect   = $false
        }
    )

    foreach ($rule in $allRule) {
        Add-Member -InputObject $rule -NotePropertyName 'RuleId' `
                   -NotePropertyValue (New-FixtureRuleId -NamePrefix $NamePrefix -ScenarioName $rule.ScenarioName)
    }

    return [pscustomobject]@{
        NamePrefix   = $NamePrefix
        ScenarioName = @($wanted)
        Table        = @($allTable  | Where-Object { $wanted -contains $_.ScenarioName })
        Parser       = @($allParser | Where-Object { $wanted -contains $_.ScenarioName } | Sort-Object Order)
        HuntingQuery = @($allHunt   | Where-Object { $wanted -contains $_.ScenarioName })
        Rule         = @($allRule   | Where-Object { $wanted -contains $_.ScenarioName })
        Alias        = @($allParser | Where-Object { $wanted -contains $_.ScenarioName } |
                            Select-Object -ExpandProperty Alias -Unique)
    }
}

#endregion

#region -- Guards --------------------------------------------------------------

function Test-KqlReferencesName {
    <#
    .SYNOPSIS
        Word-boundary, case-insensitive text match, identical to the one
        Invoke-TableMigrationReview.ps1 uses.

    .DESCRIPTION
        Duplicated here on purpose. The fixture has to assert that an indirect
        query does NOT trip the review tool's matcher, and the only honest way
        to assert that is with the same expression the review tool applies.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter()] [AllowEmptyString()] [AllowNull()] [string] $Query
      , [Parameter(Mandatory)]                           [string] $Name
    )

    if ([string]::IsNullOrEmpty($Query)) { return $false }

    return [bool]($Query -match "(?i)(?<![a-zA-Z0-9_])$([regex]::Escape($Name))(?![a-zA-Z0-9_])")
}

function Test-ReservedTableName {
    <#
    .SYNOPSIS
        True when a proposed function alias collides with a known table name.

    .DESCRIPTION
        In Log Analytics a function alias shadows a same-named table for every
        query in the workspace. Creating one on a live SIEM would silently
        repoint every detection that reads that table. The comparison is
        case-insensitive because the KQL resolver is.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)] [string] $Name
      , [Parameter()] [AllowEmptyCollection()] [AllowNull()] [string[]] $ReservedName
    )

    if (-not $ReservedName) { return $false }

    foreach ($reserved in $ReservedName) {
        if ([string]::IsNullOrWhiteSpace($reserved)) { continue }
        if ([string]::Equals($Name, $reserved, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    return $false
}

function Get-ReservedTableName {
    <#
    .SYNOPSIS
        Assembles the offline reserved-name list: the static floor plus every
        table name in the bundled solution mapping when it is available.

    .DESCRIPTION
        The live workspace table list is the authoritative guard, because it
        knows about the customer's own custom tables. This offline list is the
        belt and braces for names that could plausibly appear later, and it is
        what keeps the guard useful when the mapping file has not travelled
        with the script.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param (
        [Parameter()] [AllowEmptyString()] [AllowNull()] [string] $MappingPath
    )

    $names = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase)

    foreach ($name in $script:ReservedTableFloor) { [void]$names.Add($name) }

    if ([string]::IsNullOrWhiteSpace($MappingPath) -or -not (Test-Path -LiteralPath $MappingPath -PathType Leaf)) {
        Write-PipelineMessage "Solution mapping not found at '$MappingPath'. Falling back to the static reserved-name floor." -Level Warning
        return @($names)
    }

    try {
        # -AsHashtable is load bearing. The bundled mapping is generated from
        # upstream data that contains at least one empty-string key, and plain
        # ConvertFrom-Json refuses to build a PSCustomObject from that.
        $mapping = Get-Content -LiteralPath $MappingPath -Raw | ConvertFrom-Json -AsHashtable

        if ($mapping -and $mapping.ContainsKey('tablesToSolutions') -and $mapping['tablesToSolutions']) {
            foreach ($tableName in $mapping['tablesToSolutions'].Keys) {
                if ([string]::IsNullOrWhiteSpace($tableName)) { continue }
                [void]$names.Add([string]$tableName)
            }
        }
    }
    catch {
        Write-PipelineMessage "Could not read the solution mapping: $($_.Exception.Message.Split([char]10)[0]). Falling back to the static reserved-name floor." -Level Warning
    }

    return @($names)
}

function Get-AliasCollisionReason {
    <#
    .SYNOPSIS
        Returns a human-readable reason when a proposed function alias is
        unsafe to create, or $null when it is safe.

    .DESCRIPTION
        Three checks, in the order that matters. A collision with a live
        workspace table is the worst outcome and is reported first, because
        that is the one that silently rewrites production detections. A
        collision with a known table name that is not present today is next,
        since a solution installed later would then be shadowed. A collision
        with somebody else's existing parser is last: it would not break a
        table, but it would silently replace their query.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)] [string] $Alias
      , [Parameter()] [AllowEmptyCollection()] [AllowNull()] [string[]] $WorkspaceTableName
      , [Parameter()] [AllowEmptyCollection()] [AllowNull()] [string[]] $ReservedName
      , [Parameter()] [AllowEmptyCollection()] [AllowNull()] [string[]] $ForeignAlias
    )

    if (Test-ReservedTableName -Name $Alias -ReservedName $WorkspaceTableName) {
        return "alias '$Alias' matches a table that exists in this workspace; a function alias shadows a table for every query in the workspace"
    }

    if (Test-ReservedTableName -Name $Alias -ReservedName $ReservedName) {
        return "alias '$Alias' matches a known Log Analytics or Content Hub table name"
    }

    if (Test-ReservedTableName -Name $Alias -ReservedName $ForeignAlias) {
        return "alias '$Alias' is already used by a saved search that this fixture does not own"
    }

    return $null
}

function Get-FixtureObjectAction {
    <#
    .SYNOPSIS
        Decides what the plan says about one object: create, update, abort,
        delete, skip or absent.

    .DESCRIPTION
        Existence alone never authorises a write or a delete. An object that
        exists but does not carry the ownership marker is ABORT on the create
        path (the run stops before anything is written) and SKIP on the
        removal path (it belongs to somebody else).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter()] [AllowNull()] [object] $Existing
      , [Parameter()]              [bool]   $IsOwned
      , [Parameter()]              [switch] $ForRemoval
    )

    if ($null -eq $Existing) {
        return $(if ($ForRemoval) { 'ABSENT' } else { 'CREATE' })
    }

    if ($IsOwned) {
        return $(if ($ForRemoval) { 'DELETE' } else { 'UPDATE' })
    }

    return $(if ($ForRemoval) { 'SKIP' } else { 'ABORT' })
}

#endregion

#region -- Ownership -----------------------------------------------------------

function Get-SavedSearchTagValue {
    <#
    .SYNOPSIS
        Reads one properties.tags entry from a saved search as ARM returns it.

    .DESCRIPTION
        properties.tags is an array of {name, value} objects that round-trips
        through a GET, which makes it the one usable ownership marker on a
        saved search. Member lookup goes through PSObject.Properties so a
        missing member is data rather than a StrictMode exception, and so the
        server's casing of 'name' does not matter.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter()] [AllowNull()] [object] $SavedSearch
      , [Parameter(Mandatory)]      [string] $TagName
    )

    if ($null -eq $SavedSearch) { return $null }

    $propsMember = $SavedSearch.PSObject.Properties['properties']
    if (-not $propsMember -or $null -eq $propsMember.Value) { return $null }

    $tagMember = $propsMember.Value.PSObject.Properties['tags']
    if (-not $tagMember -or $null -eq $tagMember.Value) { return $null }

    foreach ($tag in @($tagMember.Value)) {
        if ($null -eq $tag) { continue }

        $nameMember  = $tag.PSObject.Properties['name']
        $valueMember = $tag.PSObject.Properties['value']

        if ($nameMember -and $valueMember -and
            [string]::Equals([string]$nameMember.Value, $TagName, [System.StringComparison]::OrdinalIgnoreCase)) {
            return [string]$valueMember.Value
        }
    }

    return $null
}

function Test-FixtureOwnedSavedSearch {
    <#
    .SYNOPSIS
        True when a saved search carries this script's ownership tag.

    .DESCRIPTION
        Tag based, not prefix based, so a customer object that innocently
        starts with the same prefix survives -Remove, and so a fixture object
        somebody renamed by hand is still recognised as ours.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter()] [AllowNull()] [object] $SavedSearch
      , [Parameter(Mandatory)]      [string] $FixtureMarker
    )

    $value = Get-SavedSearchTagValue -SavedSearch $SavedSearch -TagName $script:FixtureTagName
    if ([string]::IsNullOrWhiteSpace($value)) { return $false }

    return [string]::Equals($value, $FixtureMarker, [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-FixtureOwnedAlertRule {
    <#
    .SYNOPSIS
        True when an analytics rule is provably this fixture's.

    .DESCRIPTION
        Microsoft.SecurityInsights/alertRules has no ARM tags, so ownership
        rests on two markers, either of which is sufficient:

          - the resource name equals a RECOMPUTED deterministic GUID, which
            survives any edit to the display name or description
          - the description carries the '[SacFixture:<marker>:' sentinel

        A rule with alertRuleTemplateName set is Content Hub owned and can
        never be ours, so it is refused outright regardless of the above.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter()] [AllowNull()] [object] $AlertRule
      , [Parameter(Mandatory)]      [string] $FixtureMarker
      , [Parameter()] [AllowEmptyCollection()] [AllowNull()] [string[]] $ExpectedRuleId
    )

    if ($null -eq $AlertRule) { return $false }

    $propsMember = $AlertRule.PSObject.Properties['properties']
    $props       = if ($propsMember) { $propsMember.Value } else { $null }

    if ($props) {
        $templateMember = $props.PSObject.Properties['alertRuleTemplateName']
        if ($templateMember -and -not [string]::IsNullOrWhiteSpace([string]$templateMember.Value)) {
            return $false
        }
    }

    $nameMember = $AlertRule.PSObject.Properties['name']
    if ($nameMember -and $ExpectedRuleId) {
        foreach ($expected in $ExpectedRuleId) {
            if ([string]::Equals([string]$nameMember.Value, $expected, [System.StringComparison]::OrdinalIgnoreCase)) {
                return $true
            }
        }
    }

    if ($props) {
        $descMember = $props.PSObject.Properties['description']
        if ($descMember -and $descMember.Value) {
            return ([string]$descMember.Value).Contains("[$($script:FixtureTagName):${FixtureMarker}:")
        }
    }

    return $false
}

function Test-FixtureOwnedTable {
    <#
    .SYNOPSIS
        True when a table is provably this fixture's.

    .DESCRIPTION
        Four gates, all required. The name must be in the closed fixture set
        (not an open prefix glob), the table must be a CustomLog, it must carry
        the marker column that only this script's records produce, and it must
        not be one of the Microsoft-managed tables the review tool excludes.

        A table whose name matches but which has no marker column belongs to
        somebody else. That is exactly the case -RemoveUnmarkedTable exists to
        override, loudly and on purpose.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter()] [AllowNull()] [object] $Table
      , [Parameter()] [AllowEmptyCollection()] [AllowNull()] [string[]] $ExpectedTableName
    )

    if ($null -eq $Table) { return $false }

    $nameMember = $Table.PSObject.Properties['name']
    if (-not $nameMember -or [string]::IsNullOrWhiteSpace([string]$nameMember.Value)) { return $false }

    $name = [string]$nameMember.Value
    if ($name -in @('AzureDiagnostics')) { return $false }

    $matched = $false
    foreach ($expected in @($ExpectedTableName)) {
        if ([string]::Equals($name, $expected, [System.StringComparison]::OrdinalIgnoreCase)) {
            $matched = $true
            break
        }
    }
    if (-not $matched) { return $false }

    $propsMember = $Table.PSObject.Properties['properties']
    if (-not $propsMember -or $null -eq $propsMember.Value) { return $false }

    $schemaMember = $propsMember.Value.PSObject.Properties['schema']
    if (-not $schemaMember -or $null -eq $schemaMember.Value) { return $false }

    $typeMember = $schemaMember.Value.PSObject.Properties['tableType']
    if (-not $typeMember -or [string]$typeMember.Value -ne 'CustomLog') { return $false }

    $columnMember = $schemaMember.Value.PSObject.Properties['columns']
    if (-not $columnMember -or $null -eq $columnMember.Value) { return $false }

    foreach ($column in @($columnMember.Value)) {
        if ($null -eq $column) { continue }
        $colName = $column.PSObject.Properties['name']
        if ($colName -and [string]::Equals([string]$colName.Value, $script:MarkerColumnName,
                [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    return $false
}

function Get-TableSubType {
    <#
    .SYNOPSIS
        Reads properties.schema.tableSubType from a table object, or 'Unknown'.

    .DESCRIPTION
        Under StrictMode a plain property access on a missing member throws, so
        the PSObject.Properties indexer is load bearing here. Whether a table is
        still 'Classic' decides whether the Tables API will accept a DELETE at
        all, so getting this wrong turns a clear message into a raw HTTP 400.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter()] [AllowNull()] [object] $Table
    )

    if ($null -eq $Table) { return 'Unknown' }

    $propsMember = $Table.PSObject.Properties['properties']
    if (-not $propsMember -or $null -eq $propsMember.Value) { return 'Unknown' }

    $schemaMember = $propsMember.Value.PSObject.Properties['schema']
    if (-not $schemaMember -or $null -eq $schemaMember.Value) { return 'Unknown' }

    $subTypeMember = $schemaMember.Value.PSObject.Properties['tableSubType']
    if (-not $subTypeMember -or [string]::IsNullOrWhiteSpace([string]$subTypeMember.Value)) { return 'Unknown' }

    return [string]$subTypeMember.Value
}

#endregion

#region -- Body builders -------------------------------------------------------

function New-FixtureDescription {
    <#
    .SYNOPSIS
        Builds the analytics rule description, including the machine-readable
        ownership sentinel on its own final line.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure function: builds a string, changes no state.')]
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)] [string] $NamePrefix
      , [Parameter(Mandatory)] [string] $FixtureMarker
      , [Parameter(Mandatory)] [string] $RunId
      , [Parameter(Mandatory)] [string] $ScenarioName
      , [Parameter()]          [bool]   $Enabled = $false
    )

    $state = if ($Enabled) { 'ENABLED' } else { 'DISABLED' }

    return @(
        "Dependency-detection rehearsal fixture for the classic-to-DCR migration toolkit."
        "$state, incident creation off. Not a real detection. Safe to delete."
        "Remove with New-DependencyFixture.ps1 -Remove -NamePrefix $NamePrefix"
        "[$($script:FixtureTagName):${FixtureMarker}:${RunId}:${ScenarioName}]"
    ) -join "`n"
}

function New-SavedSearchBody {
    <#
    .SYNOPSIS
        Builds the savedSearches PUT body for a parser or a hunting query.

    .DESCRIPTION
        A parser is a saved search with functionAlias set; a hunting query is a
        saved search in the 'Hunting Queries' category with no alias. The
        distinction is exactly what Invoke-TableMigrationReview.ps1 classifies
        on, so the two shapes must not blur: passing an alias for the hunting
        query would land it in the Parsers bucket and the non-rule content type
        would go untested.

        etag '*' makes a re-run converge on the same object rather than
        failing. It is an unconditional overwrite, which is safe only because
        preflight aborts the whole run when a target name exists and is not
        already ours.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure function: builds a request body, changes no state.')]
    [CmdletBinding()]
    [OutputType([hashtable])]
    param (
        [Parameter(Mandatory)] [string] $Category
      , [Parameter(Mandatory)] [string] $DisplayName
      , [Parameter(Mandatory)] [string] $Query
      , [Parameter(Mandatory)] [string] $FixtureMarker
      , [Parameter(Mandatory)] [string] $RunId
      , [Parameter(Mandatory)] [string] $ScenarioName
      , [Parameter()] [AllowEmptyString()] [string] $FunctionAlias
    )

    $properties = [ordered]@{
        category    = $Category
        displayName = $DisplayName
        query       = $Query
        version     = 2
        tags        = @(
            [ordered]@{ name = $script:FixtureTagName;  value = $FixtureMarker }
            [ordered]@{ name = $script:FixtureRunTag;   value = $RunId }
            [ordered]@{ name = $script:FixtureScenTag;  value = $ScenarioName }
        )
    }

    if (-not [string]::IsNullOrWhiteSpace($FunctionAlias)) {
        $properties['functionAlias'] = $FunctionAlias
    }

    return @{
        etag       = '*'
        properties = $properties
    }
}

function New-AlertRuleBody {
    <#
    .SYNOPSIS
        Builds the Scheduled analytics rule PUT body.

    .DESCRIPTION
        Ten properties are required at api-version 2024-03-01, and two of them
        are easy to miss: suppressionDuration and suppressionEnabled. Omitting
        either is an HTTP 400, and suppressionDuration is required even when
        suppressionEnabled is false.

        The durations are ISO 8601 ('PT24H'), not the KQL timespan format that
        the repository's YAML rule content uses. Sending '24h' here is a 400.

        Four independent things stop a fixture rule ever paging anyone, and
        three of them survive somebody flipping 'enabled' by hand in the
        portal: the zero-row clamp on the query, createIncident false, and
        Informational severity.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure function: builds a request body, changes no state.')]
    [CmdletBinding()]
    [OutputType([hashtable])]
    param (
        [Parameter(Mandatory)] [string] $DisplayName
      , [Parameter(Mandatory)] [string] $Description
      , [Parameter(Mandatory)] [string] $Query
      , [Parameter()]          [bool]   $Enabled        = $false
      , [Parameter()]          [string] $QueryFrequency = 'PT24H'
      , [Parameter()]          [string] $QueryPeriod    = 'PT24H'
      , [Parameter()]          [string] $Severity       = 'Informational'
    )

    return @{
        kind       = 'Scheduled'
        properties = [ordered]@{
            displayName           = $DisplayName
            description           = $Description
            severity              = $Severity
            enabled               = $Enabled
            query                 = $Query
            queryFrequency        = $QueryFrequency
            queryPeriod           = $QueryPeriod
            triggerOperator       = 'GreaterThan'
            triggerThreshold      = 0
            suppressionDuration   = 'PT1H'
            suppressionEnabled    = $false
            eventGroupingSettings = [ordered]@{ aggregationKind = 'SingleAlert' }
            incidentConfiguration = [ordered]@{
                createIncident        = $false
                groupingConfiguration = [ordered]@{
                    enabled              = $false
                    reopenClosedIncident = $false
                    lookbackDuration     = 'PT5H'
                    matchingMethod       = 'AllEntities'
                }
            }
        }
    }
}

#endregion

#region -- Resource paths ------------------------------------------------------

function Get-FixtureResourcePath {
    <#
    .SYNOPSIS
        Builds the relative ARM paths this script uses, so the api-version and
        the provider casing live in one place.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)] [string] $SubscriptionId
      , [Parameter(Mandatory)] [string] $ResourceGroupName
      , [Parameter(Mandatory)] [string] $WorkspaceName
    )

    $workspaceBase = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName" +
                     "/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName"

    return [pscustomobject]@{
        WorkspaceBase = $workspaceBase
        SentinelBase  = "$workspaceBase/providers/Microsoft.SecurityInsights"
        TableList     = "$workspaceBase/tables?api-version=$script:TablesApiVersion"
        SavedList     = "$workspaceBase/savedSearches?api-version=$script:SavedSearchApiVersion"
        RuleList      = "$workspaceBase/providers/Microsoft.SecurityInsights/alertRules?api-version=$script:SentinelApiVersion"
        Onboarding    = "$workspaceBase/providers/Microsoft.SecurityInsights/onboardingStates/default?api-version=$script:SentinelApiVersion"
    }
}

#endregion

#region -- Context and preflight ----------------------------------------------

Write-PipelineMessage 'Dependency fixture' -Level Section

if ($EnableRulesWithLiveQuery -and -not $EnableRules) {
    throw '-EnableRulesWithLiveQuery only has meaning with -EnableRules. Two separate switches are required on purpose, so neither can be reached by a typo.'
}

if ($MigrateBeforeRemove -and -not $Remove) {
    throw '-MigrateBeforeRemove only has meaning with -Remove.'
}

if ($RemoveUnmarkedTable -and -not $Remove) {
    throw '-RemoveUnmarkedTable only has meaning with -Remove.'
}

$context = Get-AzContext
if (-not $context) {
    throw 'No Az context found. Run Connect-AzAccount first.'
}

if ($SubscriptionId -and $context.Subscription.Id -ne $SubscriptionId) {
    # Selecting a subscription changes only this session's client-side context;
    # it mutates nothing in Azure, so it must still happen under -WhatIf or the
    # plan would be built against the wrong subscription. Set-AzContext does
    # support ShouldProcess, and under -WhatIf it returns nothing, which would
    # leave $context null and make the Subscription check below throw under
    # Set-StrictMode. Suppress WhatIf for this call and re-read the context.
    $null   = Set-AzContext -Subscription $SubscriptionId -WhatIf:$false
    $context = Get-AzContext
}

if (-not $context.Subscription) {
    throw 'Az context has no subscription selected. Run Connect-AzAccount or Set-AzContext -Subscription <id> first.'
}

$resolvedSubscriptionId = $context.Subscription.Id

try {
    $workspace = Get-AzOperationalInsightsWorkspace -ResourceGroupName $ResourceGroupName -Name $WorkspaceName
}
catch {
    throw "Could not read workspace '$WorkspaceName' in resource group '$ResourceGroupName': $($_.Exception.Message.Split([char]10)[0])"
}

$workspaceCustomerId = $workspace.CustomerId
$paths   = Get-FixtureResourcePath -SubscriptionId $resolvedSubscriptionId `
                                   -ResourceGroupName $ResourceGroupName -WorkspaceName $WorkspaceName

$runId   = [guid]::NewGuid().ToString()
$clamp   = if ($EnableRulesWithLiveQuery) { '' } else { $script:QueryClamp }
$plan    = Get-FixtureNamingPlan -NamePrefix $NamePrefix -ScenarioName $Scenario -QueryClamp $clamp

$script:SharedKey = $null

# ---- read-only probes. These all run under -WhatIf, because they are what
# ---- make the plan real rather than notional, and none of them writes.

Write-PipelineMessage 'Preflight' -Level Section

$onboarding = Invoke-AzRestMethod -Path $paths.Onboarding -Method GET
if ($onboarding.StatusCode -eq 404) {
    throw "Microsoft Sentinel is not onboarded on workspace '$WorkspaceName'. The analytics rules could never be created, and a partial fixture is worse than none."
}
if ($onboarding.StatusCode -ne 200) {
    Write-PipelineMessage "Could not confirm the Sentinel onboarding state (HTTP $($onboarding.StatusCode)). Continuing, but analytics rule creation may fail." -Level Warning
}

$existingTable  = @(Get-ArmCollection -Uri $paths.TableList)
$existingSaved  = @(Get-ArmCollection -Uri $paths.SavedList)
$existingRule   = @(Get-ArmCollection -Uri $paths.RuleList)

Write-PipelineMessage "Read $($existingTable.Count) tables, $($existingSaved.Count) saved searches, $($existingRule.Count) analytics rules."

$workspaceTableName = @($existingTable | ForEach-Object {
    $member = $_.PSObject.Properties['name']
    if ($member) { [string]$member.Value }
})

$expectedRuleId   = @($plan.Rule | Select-Object -ExpandProperty RuleId -Unique)
$expectedTableName = @($plan.Table | Select-Object -ExpandProperty TableName -Unique)

# Aliases owned by this fixture are not foreign, so a re-run is an update
# rather than a refusal.
$foreignAlias = @($existingSaved | Where-Object {
    -not (Test-FixtureOwnedSavedSearch -SavedSearch $_ -FixtureMarker $script:FixtureMarker)
} | ForEach-Object {
    $propsMember = $_.PSObject.Properties['properties']
    if ($propsMember -and $propsMember.Value) {
        $aliasMember = $propsMember.Value.PSObject.Properties['functionAlias']
        if ($aliasMember -and -not [string]::IsNullOrWhiteSpace([string]$aliasMember.Value)) {
            [string]$aliasMember.Value
        }
    }
})

#endregion

#region -- Plan ----------------------------------------------------------------

function Find-ExistingByName {
    <#
    .SYNOPSIS
        Finds an item in an ARM collection by its resource 'name' property.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param (
        [Parameter()] [AllowEmptyCollection()] [AllowNull()] [object[]] $Collection
      , [Parameter(Mandatory)]                               [string]   $Name
    )

    foreach ($item in @($Collection)) {
        if ($null -eq $item) { continue }

        $itemName = $null
        $member   = $item.PSObject.Properties['name']
        if ($member -and $member.Value) {
            $itemName = [string]$member.Value
        }
        else {
            # Microsoft's documented savedSearches response samples carry only
            # id, etag and properties, with no 'name'. Live ARM does return it,
            # but relying on that alone means an unexpected shape reads as "no
            # such object", and the caller would then PUT over a pre-existing
            # customer parser with If-Match '*'. Recover the name from the
            # resource id instead so a collision is still detected.
            $idMember = $item.PSObject.Properties['id']
            if ($idMember -and $idMember.Value) {
                $itemName = ([string]$idMember.Value -split '/')[-1]
            }
        }

        if ($itemName -and [string]::Equals($itemName, $Name, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $item
        }
    }

    return $null
}

$planRow = [System.Collections.Generic.List[pscustomobject]]::new()

foreach ($table in $plan.Table) {
    $found  = Find-ExistingByName -Collection $existingTable -Name $table.TableName
    $owned  = Test-FixtureOwnedTable -Table $found -ExpectedTableName $expectedTableName
    $action = Get-FixtureObjectAction -Existing $found -IsOwned $owned -ForRemoval:$Remove

    $planRow.Add([pscustomobject]@{
        Type       = 'Table'
        Name       = $table.TableName
        ResourceId = "$($paths.WorkspaceBase)/tables/$($table.TableName)"
        Scenario   = $table.ScenarioName
        Action     = $action
        Marker     = $(if ($owned) { $script:MarkerColumnName } else { '' })
    })
}

foreach ($parser in ($plan.Parser | Where-Object { -not $_.IsCycleClosure })) {
    $found  = Find-ExistingByName -Collection $existingSaved -Name $parser.SavedSearchId
    $owned  = Test-FixtureOwnedSavedSearch -SavedSearch $found -FixtureMarker $script:FixtureMarker
    $action = Get-FixtureObjectAction -Existing $found -IsOwned $owned -ForRemoval:$Remove

    $planRow.Add([pscustomobject]@{
        Type       = 'Parser'
        Name       = "$($parser.SavedSearchId) (alias $($parser.Alias))"
        ResourceId = "$($paths.WorkspaceBase)/savedSearches/$($parser.SavedSearchId)"
        Scenario   = $parser.ScenarioName
        Action     = $action
        Marker     = $(if ($owned) { "tag $($script:FixtureTagName)" } else { '' })
    })
}

foreach ($hunt in $plan.HuntingQuery) {
    $found  = Find-ExistingByName -Collection $existingSaved -Name $hunt.SavedSearchId
    $owned  = Test-FixtureOwnedSavedSearch -SavedSearch $found -FixtureMarker $script:FixtureMarker
    $action = Get-FixtureObjectAction -Existing $found -IsOwned $owned -ForRemoval:$Remove

    $planRow.Add([pscustomobject]@{
        Type       = 'HuntingQuery'
        Name       = $hunt.SavedSearchId
        ResourceId = "$($paths.WorkspaceBase)/savedSearches/$($hunt.SavedSearchId)"
        Scenario   = $hunt.ScenarioName
        Action     = $action
        Marker     = $(if ($owned) { "tag $($script:FixtureTagName)" } else { '' })
    })
}

foreach ($rule in $plan.Rule) {
    $found  = Find-ExistingByName -Collection $existingRule -Name $rule.RuleId
    $owned  = Test-FixtureOwnedAlertRule -AlertRule $found -FixtureMarker $script:FixtureMarker -ExpectedRuleId $expectedRuleId
    $action = Get-FixtureObjectAction -Existing $found -IsOwned $owned -ForRemoval:$Remove

    $planRow.Add([pscustomobject]@{
        Type       = 'AlertRule'
        Name       = "$($rule.RuleId)  $($rule.DisplayName)"
        ResourceId = "$($paths.SentinelBase)/alertRules/$($rule.RuleId)"
        Scenario   = $rule.ScenarioName
        Action     = $action
        Marker     = $(if ($owned) { 'derived id / description sentinel' } else { '' })
    })
}

# On the removal path, also surface fixture-owned strays: objects carrying the
# marker whose names are not in the current plan, for example from a run with a
# different -Scenario selection.
if ($Remove) {
    $plannedSavedName = @($planRow | Where-Object { $_.Type -in @('Parser', 'HuntingQuery') } |
                          ForEach-Object { ($_.ResourceId -split '/')[-1] })

    foreach ($saved in $existingSaved) {
        $member = $saved.PSObject.Properties['name']
        $name   = $null
        if ($member -and $member.Value) {
            $name = [string]$member.Value
        }
        else {
            $idMember = $saved.PSObject.Properties['id']
            if ($idMember -and $idMember.Value) { $name = ([string]$idMember.Value -split '/')[-1] }
        }
        if (-not $name) { continue }
        if ($name -in $plannedSavedName) { continue }

        # The fixture marker is deliberately prefix-independent, so on its own it
        # matches every fixture ever created in this workspace. Scope the sweep to
        # the prefix being removed, otherwise '-Remove -NamePrefix Bravo' would
        # also delete a concurrent 'Alpha' fixture's parsers and hunting queries.
        if ($name -notlike "$NamePrefix*") { continue }

        if (-not (Test-FixtureOwnedSavedSearch -SavedSearch $saved -FixtureMarker $script:FixtureMarker)) { continue }

        $planRow.Add([pscustomobject]@{
            Type       = 'SavedSearch'
            Name       = $name
            ResourceId = "$($paths.WorkspaceBase)/savedSearches/$name"
            Scenario   = 'stray'
            Action     = 'DELETE'
            Marker     = "tag $($script:FixtureTagName)"
        })
    }
}

$abortRow = @($planRow | Where-Object { $_.Action -eq 'ABORT' })

#endregion

#region -- Alias guard ---------------------------------------------------------

$aliasProblem = @()

if (-not $Remove) {
    $reservedName = Get-ReservedTableName -MappingPath $script:MappingPath

    foreach ($alias in $plan.Alias) {
        $reason = Get-AliasCollisionReason -Alias $alias `
                                           -WorkspaceTableName $workspaceTableName `
                                           -ReservedName $reservedName `
                                           -ForeignAlias $foreignAlias
        if ($reason) { $aliasProblem += $reason }
    }
}

# A fixture that quietly proves the wrong thing is worse than no fixture, so
# assert the indirect content really is indirect before anything is written.
$queryProblem = @()

if (-not $Remove) {
    foreach ($rule in ($plan.Rule | Where-Object { $_.IsIndirect })) {
        foreach ($tableName in $expectedTableName) {
            if (Test-KqlReferencesName -Query $rule.Query -Name $tableName) {
                $queryProblem += "indirect rule '$($rule.DisplayName)' names table '$tableName' in its query, which would make the fixture prove nothing"
            }
        }
    }

    foreach ($hunt in $plan.HuntingQuery) {
        foreach ($tableName in $expectedTableName) {
            if (Test-KqlReferencesName -Query $hunt.Query -Name $tableName) {
                $queryProblem += "hunting query '$($hunt.SavedSearchId)' names table '$tableName' in its query, which would make the fixture prove nothing"
            }
        }
    }

    $everyQuery = [System.Collections.Generic.List[string]]::new()
    foreach ($parser in $plan.Parser)     { $everyQuery.Add($parser.Query) }
    foreach ($hunt in $plan.HuntingQuery) { $everyQuery.Add($hunt.Query) }
    foreach ($rule in $plan.Rule)         { $everyQuery.Add($rule.Query) }

    $orphan = @($plan.Table | Where-Object { $_.ScenarioName -eq 'Orphan' })
    foreach ($orphanTable in $orphan) {
        foreach ($query in $everyQuery) {
            if (Test-KqlReferencesName -Query $query -Name $orphanTable.TableName) {
                $queryProblem += "the orphan table '$($orphanTable.TableName)' is referenced by fixture content, so it could not prove the absence of over-reporting"
            }
        }
    }
}

#endregion

#region -- Plan banner ---------------------------------------------------------

$mode = if ($Remove) { 'REMOVE' } else { 'CREATE' }

Write-PipelineMessage "Dependency fixture plan ($mode)" -Level Section
Write-PipelineMessage "  Subscription     : $resolvedSubscriptionId"
Write-PipelineMessage "  Resource group   : $ResourceGroupName"
Write-PipelineMessage "  Workspace        : $WorkspaceName (customer id $workspaceCustomerId)"
Write-PipelineMessage "  Name prefix      : $NamePrefix"
Write-PipelineMessage "  Fixture marker   : $script:FixtureMarker"
Write-PipelineMessage "  Run id           : $runId"
Write-PipelineMessage "  Scenarios        : $($plan.ScenarioName -join ', ')"

if (-not $Remove) {
    $ruleState = if ($EnableRules) { 'ENABLED' } else { 'DISABLED' }
    $clampText = if ($EnableRulesWithLiveQuery) { 'NO zero-row clamp' } else { "clamped with '$script:QueryClamp'" }

    Write-PipelineMessage ("  Will create      : {0} x table, {1} x parser, {2} x hunting query, {3} x analytics rule" -f `
        $plan.Table.Count, @($plan.Parser | Where-Object { -not $_.IsCycleClosure }).Count,
        $plan.HuntingQuery.Count, $plan.Rule.Count)
    Write-PipelineMessage "  Analytics rules  : $ruleState, createIncident=false, $clampText"
    Write-PipelineMessage ("  Ingestion        : {0} records total, roughly {1} KB (billable, cannot be recalled)" -f `
        ($RecordCount * $plan.Table.Count), [math]::Max(1, [math]::Round(($RecordCount * $plan.Table.Count * 220) / 1024, 0)))

    if ($EnableRules) {
        Write-PipelineMessage "The fixture analytics rules will be created ENABLED in workspace '$WorkspaceName'. They will execute on a schedule against production data." -Level Warning
        Write-PipelineMessage 'Incident creation stays off, and Informational severity is retained.' -Level Warning
        if ($EnableRulesWithLiveQuery) {
            Write-PipelineMessage 'The zero-row clamp has ALSO been removed. This is the only configuration in which a fixture rule can raise an alert.' -Level Warning
        }
    }
}

Write-PipelineMessage ''
foreach ($row in $planRow) {
    $marker = if ($row.Marker) { "  [marker: $($row.Marker)]" } else { '' }
    Write-PipelineMessage ("  {0,-8} {1,-13} {2}{3}" -f $row.Action, $row.Type, $row.Name, $marker)
}
Write-PipelineMessage ''

if (-not $Remove) {
    Write-PipelineMessage 'Nothing has been created yet.'
}

if ($aliasProblem.Count -gt 0) {
    foreach ($problem in $aliasProblem) {
        Write-PipelineMessage "Alias guard: $problem" -Level Error
    }
    throw 'Refusing to create the fixture. A function alias would shadow a table or an existing parser for every query in this workspace. Pick a different -NamePrefix.'
}

if ($queryProblem.Count -gt 0) {
    foreach ($problem in $queryProblem) {
        Write-PipelineMessage "Fixture self-check: $problem" -Level Error
    }
    throw 'Refusing to create the fixture. The generated content would not prove what it claims to prove.'
}

if ($abortRow.Count -gt 0) {
    foreach ($row in $abortRow) {
        Write-PipelineMessage "Name collision: $($row.Type) '$($row.Name)' already exists and does not carry this fixture's marker." -Level Error
    }
    throw 'Refusing to create the fixture. One or more target names belong to existing content. Nothing was written. Pick a different -NamePrefix.'
}

#endregion

#region -- Remove --------------------------------------------------------------

if ($Remove) {
    Write-PipelineMessage 'Removing fixture' -Level Section

    $removed = [System.Collections.Generic.List[string]]::new()
    $skipped = [System.Collections.Generic.List[string]]::new()
    $failed  = [System.Collections.Generic.List[string]]::new()

    # Teardown is the reverse of creation. Analytics rules first: they are the
    # only objects that can execute, so a mid-teardown failure must never leave
    # a live rule pointing at a half-dismantled parser chain. Every delete gets
    # its own try/catch and failures accumulate, because a table stuck on
    # Classic must not strand the rules.

    foreach ($row in ($planRow | Where-Object { $_.Type -eq 'AlertRule' })) {
        if ($row.Action -ne 'DELETE') {
            if ($row.Action -eq 'SKIP') {
                Write-PipelineMessage "SKIP (not owned): $($row.ResourceId)" -Level Warning
                $skipped.Add($row.ResourceId)
            }
            continue
        }

        try {
            if ($PSCmdlet.ShouldProcess($row.ResourceId, 'Delete fixture analytics rule')) {
                Invoke-ArmRequest -Uri "$($row.ResourceId)?api-version=$script:SentinelApiVersion" `
                                  -Method DELETE -SuccessCode @(200, 204, 404) | Out-Null
                Write-PipelineMessage "Deleted analytics rule $($row.Name)." -Level Success
                $removed.Add($row.ResourceId)
            }
        }
        catch {
            Write-PipelineMessage "Failed to delete $($row.ResourceId): $($_.Exception.Message.Split([char]10)[0])" -Level Warning
            $failed.Add($row.ResourceId)
        }
    }

    # Then the saved searches: hunting query, then parsers outermost first, so
    # there is never an intermediate state where a live, reachable parser
    # depends on an alias that has just vanished.
    $savedOrder = @($planRow | Where-Object { $_.Type -eq 'HuntingQuery' }) +
                  @($planRow | Where-Object { $_.Type -eq 'SavedSearch' }) +
                  @($planRow | Where-Object { $_.Type -eq 'Parser' } | Sort-Object -Property Name -Descending)

    foreach ($row in $savedOrder) {
        if ($row.Action -ne 'DELETE') {
            if ($row.Action -eq 'SKIP') {
                Write-PipelineMessage "SKIP (not owned): $($row.ResourceId)" -Level Warning
                $skipped.Add($row.ResourceId)
            }
            continue
        }

        try {
            if ($PSCmdlet.ShouldProcess($row.ResourceId, 'Delete fixture saved search')) {
                # The saved-search contract documents only 200, and does not
                # document a 404 for a missing object. Accepting 404 anyway is
                # what makes a re-run of -Remove idempotent instead of
                # confusing.
                Invoke-ArmRequest -Uri "$($row.ResourceId)?api-version=$script:SavedSearchApiVersion" `
                                  -Method DELETE -SuccessCode @(200, 204, 404) | Out-Null
                Write-PipelineMessage "Deleted saved search $($row.Name)." -Level Success
                $removed.Add($row.ResourceId)
            }
        }
        catch {
            Write-PipelineMessage "Failed to delete $($row.ResourceId): $($_.Exception.Message.Split([char]10)[0])" -Level Warning
            $failed.Add($row.ResourceId)
        }
    }

    # Tables last. A parser left pointing at a deleted table is harmless text;
    # a table deleted under a live parser is confusing.
    foreach ($row in ($planRow | Where-Object { $_.Type -eq 'Table' })) {
        $tableName = $row.Name

        if ($row.Action -eq 'ABSENT') {
            Write-PipelineMessage "$tableName does not exist (already removed)." -Level Success
            continue
        }

        if ($row.Action -eq 'SKIP') {
            if (-not $RemoveUnmarkedTable) {
                Write-PipelineMessage "$tableName exists but carries no '$($script:MarkerColumnName)' column, so this fixture cannot prove it owns it. Left alone." -Level Warning
                Write-PipelineMessage "If you are certain it is yours, re-run with -RemoveUnmarkedTable. That switch can delete somebody else's table." -Level Warning
                $skipped.Add($row.ResourceId)
                continue
            }

            Write-PipelineMessage "$tableName carries no ownership marker. -RemoveUnmarkedTable was passed, so it will be deleted anyway." -Level Warning
        }

        try {
            $tableUri = "$($row.ResourceId)?api-version=$script:TablesApiVersion"
            $existing = Invoke-AzRestMethod -Path $tableUri -Method GET

            if ($existing.StatusCode -eq 404) {
                Write-PipelineMessage "$tableName does not exist (already removed)." -Level Success
                continue
            }
            if ($existing.StatusCode -ne 200) {
                throw "Could not read $tableName before removal: HTTP $($existing.StatusCode) $($existing.Content)"
            }

            $detail  = $existing.Content | ConvertFrom-Json
            $subType = Get-TableSubType -Table $detail

            if ($subType -eq 'Classic') {
                if (-not $MigrateBeforeRemove) {
                    Write-PipelineMessage "$tableName is still a Classic table, which the Tables API cannot delete." -Level Warning
                    Write-PipelineMessage 'Re-run with -MigrateBeforeRemove to migrate it (one-way) and then delete, or delete it in the Azure portal.' -Level Warning
                    $skipped.Add($row.ResourceId)
                    continue
                }

                if ($PSCmdlet.ShouldProcess("$WorkspaceName/$tableName", 'Migrate (irreversible) then delete')) {
                    Write-PipelineMessage 'Migrating the Classic table so it becomes deletable. This is one-way.' -Level Warning
                    Invoke-AzOperationalInsightsMigrateTable -ResourceGroupName $ResourceGroupName `
                                                             -WorkspaceName $WorkspaceName `
                                                             -TableName $tableName -Confirm:$false | Out-Null
                }
                else {
                    continue
                }
            }

            if ($PSCmdlet.ShouldProcess("$WorkspaceName/$tableName", 'Delete fixture table')) {
                Invoke-ArmRequest -Uri $tableUri -Method DELETE -SuccessCode @(200, 202, 204, 404) | Out-Null
                Write-PipelineMessage "Deleted $tableName." -Level Success
                $removed.Add($row.ResourceId)
            }
        }
        catch {
            Write-PipelineMessage "Failed to remove $tableName : $($_.Exception.Message.Split([char]10)[0])" -Level Warning
            $failed.Add($row.ResourceId)
        }
    }

    Write-PipelineMessage 'Removal summary' -Level Section
    Write-PipelineMessage "  Removed : $($removed.Count)"
    Write-PipelineMessage "  Skipped : $($skipped.Count)"
    Write-PipelineMessage "  Failed  : $($failed.Count)"

    if ($failed.Count -gt 0) {
        Write-PipelineMessage 'One or more objects could not be removed. See the warnings above.' -Level Warning
    }

    [pscustomobject]@{
        Mode          = 'Remove'
        NamePrefix    = $NamePrefix
        FixtureMarker = $script:FixtureMarker
        RunId         = $runId
        WorkspaceName = $WorkspaceName
        Removed       = $removed.ToArray()
        Skipped       = $skipped.ToArray()
        Failed        = $failed.ToArray()
    }

    return
}

#endregion

#region -- Create: tables ------------------------------------------------------

Write-PipelineMessage 'Seeding classic tables' -Level Section
Write-PipelineMessage 'The HTTP Data Collector API retires on 2026-09-14. After that date classic tables cannot be created at all.' -Level Warning

$created = [System.Collections.Generic.List[string]]::new()
$skipped = [System.Collections.Generic.List[string]]::new()
$failed  = [System.Collections.Generic.List[string]]::new()

$ingestUri = "https://$workspaceCustomerId.$OdsEndpointSuffix/api/logs?api-version=$script:DataCollectorApiVersion"
$markerValue = "$script:FixtureMarker|$runId"
$seededTable = [System.Collections.Generic.List[string]]::new()

foreach ($table in $plan.Table) {
    $row = $planRow | Where-Object { $_.Type -eq 'Table' -and $_.Name -eq $table.TableName } | Select-Object -First 1

    if ($row -and $row.Action -eq 'UPDATE' -and -not $Reseed) {
        Write-PipelineMessage "$($table.TableName) already exists and is marked as this fixture's. Skipping the seed (pass -Reseed to post again)."
        $skipped.Add($row.ResourceId)
        continue
    }

    if (-not $PSCmdlet.ShouldProcess("$WorkspaceName/$($table.TableName)",
            "Post $RecordCount fixture records via Data Collector API")) {
        Write-PipelineMessage "Skipped seeding $($table.TableName)." -Level Warning
        continue
    }

    # The shared key is fetched through the authenticated Az session, only
    # after the first ShouldProcess gate has passed, so -WhatIf performs no
    # privileged listKeys call. It is kept in memory and never printed.
    if (-not $script:SharedKey) {
        $keys = Get-AzOperationalInsightsWorkspaceSharedKey -ResourceGroupName $ResourceGroupName -Name $WorkspaceName
        $script:SharedKey = $keys.PrimarySharedKey

        if ([string]::IsNullOrWhiteSpace($script:SharedKey)) {
            throw 'Could not retrieve the workspace primary shared key. Confirm you have Log Analytics Contributor on the workspace.'
        }
    }

    try {
        $records = New-DependencyFixtureRecord -Count $RecordCount -ReferenceTime ([datetime]::UtcNow) `
                                               -Marker $markerValue -ScenarioName $table.ScenarioName

        Send-DataCollectorBatch -IngestUri $ingestUri -WorkspaceId $workspaceCustomerId `
                                -SharedKey $script:SharedKey -LogType $table.LogType -Record $records

        Write-PipelineMessage "Posted $RecordCount records to $($table.TableName)." -Level Success
        $created.Add("$($paths.WorkspaceBase)/tables/$($table.TableName)")
        $seededTable.Add($table.TableName)
    }
    catch {
        Write-PipelineMessage "Failed to seed $($table.TableName): $($_.Exception.Message.Split([char]10)[0])" -Level Warning
        $failed.Add("$($paths.WorkspaceBase)/tables/$($table.TableName)")
    }
}

#endregion

#region -- Create: wait for the tables ----------------------------------------

# Two separate events, and the gap between them is the whole problem. A table
# becoming visible through the Tables API is necessary but NOT sufficient: the
# analytics rule validator resolves names against the KQL engine, which lags.
# Polling only the Tables API and then PUTting a rule is the failure this
# ordering exists to avoid.

$tableToWaitFor = @($plan.Table | Where-Object { $seededTable -contains $_.TableName })

if ($tableToWaitFor.Count -gt 0) {
    Write-PipelineMessage 'Waiting for the tables to become queryable' -Level Section
    Write-PipelineMessage 'A table resource usually appears within a few minutes. Becoming resolvable by the query engine is separate and slower, and it is what the analytics rule validator needs.'

    $tableIndex = 0

    foreach ($table in $tableToWaitFor) {
        $tableIndex++

        # Each table gets its own budget. A single shared deadline computed
        # before the loop meant a slow first table could consume the whole
        # allowance and leave every later table without even one attempt.
        $deadline = [datetime]::UtcNow.AddSeconds($TimeoutSeconds)
        $started  = [datetime]::UtcNow

        $tableUri = "$($paths.WorkspaceBase)/tables/$($table.TableName)?api-version=$script:TablesApiVersion"
        $subType  = $null
        $poll     = 0

        while ([datetime]::UtcNow -lt $deadline) {
            try {
                $response = Invoke-ArmRequest -Uri $tableUri -Method GET -SuccessCode @(200)
                $subType  = Get-TableSubType -Table ($response.Content | ConvertFrom-Json)
                if ($subType -ne 'Unknown') { break }
            }
            catch {
                Write-Verbose "Table $($table.TableName) not present yet: $($_.Exception.Message.Split([char]10)[0])"
            }

            $poll++
            # A silent wait of up to $TimeoutSeconds reads as a hang, and a tool
            # that looks hung gets killed halfway, leaving a partial fixture to
            # clean up. Report every fourth poll, so about once a minute.
            if ($poll % 4 -eq 0) {
                $waited = [int]([datetime]::UtcNow - $started).TotalSeconds
                Write-PipelineMessage ("  still waiting for {0} ({1} of {2}), {3}s elapsed of {4}s allowed" -f `
                    $table.TableName, $tableIndex, $tableToWaitFor.Count, $waited, $TimeoutSeconds)
            }

            Start-Sleep -Seconds 15
        }

        if (-not $subType -or $subType -eq 'Unknown') {
            Write-PipelineMessage "$($table.TableName) did not appear within the timeout. The rules that depend on it will probably fail to validate." -Level Warning
            continue
        }

        Write-PipelineMessage "$($table.TableName) is present. tableSubType = $subType."
        if ($subType -ne 'Classic') {
            Write-PipelineMessage "Expected 'Classic' but got '$subType'. The Data Collector API should have produced a classic table." -Level Warning
        }

        # Second gate: actual queryability. A semantic error means not ready.
        $queryable = $false
        while ([datetime]::UtcNow -lt $deadline) {
            try {
                Invoke-AzOperationalInsightsQuery -WorkspaceId $workspaceCustomerId `
                                                  -Query "$($table.TableName) | take 1" -ErrorAction Stop | Out-Null
                $queryable = $true
                break
            }
            catch {
                Write-Verbose "Table $($table.TableName) not queryable yet: $($_.Exception.Message.Split([char]10)[0])"
                Start-Sleep -Seconds 15
            }
        }

        if ($queryable) {
            Write-PipelineMessage "$($table.TableName) is queryable." -Level Success
        }
        else {
            Write-PipelineMessage "$($table.TableName) is not queryable yet. Rule creation may fail with 'Failed to resolve table or column expression named'." -Level Warning
        }
    }
}

#endregion

#region -- Create: parsers and hunting query ----------------------------------

Write-PipelineMessage 'Creating parsers' -Level Section
Write-PipelineMessage 'Saved searches are not validated server side, so these save whether or not the tables have finished materialising. They are still created in dependency order so a partial failure leaves a sane state.'

foreach ($parser in $plan.Parser) {
    $savedUri  = "$($paths.WorkspaceBase)/savedSearches/$($parser.SavedSearchId)?api-version=$script:SavedSearchApiVersion"
    $resource  = "$($paths.WorkspaceBase)/savedSearches/$($parser.SavedSearchId)"

    $action = if ($parser.IsCycleClosure) {
        'Update fixture parser to close the reference cycle'
    }
    else {
        "Create fixture parser (alias $($parser.Alias))"
    }

    if (-not $PSCmdlet.ShouldProcess($resource, $action)) {
        Write-PipelineMessage "Skipped $($parser.SavedSearchId)." -Level Warning
        continue
    }

    try {
        $body = New-SavedSearchBody -Category "$NamePrefix Fixture" -DisplayName $parser.DisplayName `
                                    -Query $parser.Query -FunctionAlias $parser.Alias `
                                    -FixtureMarker $script:FixtureMarker -RunId $runId `
                                    -ScenarioName $parser.ScenarioName

        Invoke-ArmRequest -Uri $savedUri -Method PUT -Payload (ConvertTo-Json -InputObject $body -Depth 10) `
                          -SuccessCode @(200, 201) | Out-Null

        $verb = if ($parser.IsCycleClosure) { 'Closed the cycle on' } else { 'Created' }
        Write-PipelineMessage "$verb parser $($parser.SavedSearchId) (alias $($parser.Alias))." -Level Success

        if (-not $parser.IsCycleClosure) { $created.Add($resource) }
    }
    catch {
        Write-PipelineMessage "Failed to write $($parser.SavedSearchId): $($_.Exception.Message.Split([char]10)[0])" -Level Warning
        $failed.Add($resource)
    }
}

foreach ($hunt in $plan.HuntingQuery) {
    $savedUri = "$($paths.WorkspaceBase)/savedSearches/$($hunt.SavedSearchId)?api-version=$script:SavedSearchApiVersion"
    $resource = "$($paths.WorkspaceBase)/savedSearches/$($hunt.SavedSearchId)"

    if (-not $PSCmdlet.ShouldProcess($resource, 'Create fixture hunting query')) {
        Write-PipelineMessage "Skipped $($hunt.SavedSearchId)." -Level Warning
        continue
    }

    try {
        # No functionAlias, and category 'Hunting Queries', so the review tool
        # classifies this as a hunting query rather than a parser.
        $body = New-SavedSearchBody -Category 'Hunting Queries' -DisplayName $hunt.DisplayName `
                                    -Query $hunt.Query -FixtureMarker $script:FixtureMarker `
                                    -RunId $runId -ScenarioName $hunt.ScenarioName

        Invoke-ArmRequest -Uri $savedUri -Method PUT -Payload (ConvertTo-Json -InputObject $body -Depth 10) `
                          -SuccessCode @(200, 201) | Out-Null

        Write-PipelineMessage "Created hunting query $($hunt.SavedSearchId)." -Level Success
        $created.Add($resource)
    }
    catch {
        Write-PipelineMessage "Failed to write $($hunt.SavedSearchId): $($_.Exception.Message.Split([char]10)[0])" -Level Warning
        $failed.Add($resource)
    }
}

#endregion

#region -- Create: analytics rules --------------------------------------------

Write-PipelineMessage 'Creating analytics rules' -Level Section
Write-PipelineMessage 'Rules go last. Sentinel validates a rule query against the workspace schema on write, so every table and every parser in the chain has to resolve first.'

$ruleEnabled = [bool]$EnableRules

foreach ($rule in $plan.Rule) {
    $ruleUri  = "$($paths.SentinelBase)/alertRules/$($rule.RuleId)?api-version=$script:SentinelApiVersion"
    $resource = "$($paths.SentinelBase)/alertRules/$($rule.RuleId)"

    $action = if ($ruleEnabled) { 'Create ENABLED fixture analytics rule' } else { 'Create DISABLED fixture analytics rule' }

    if (-not $PSCmdlet.ShouldProcess($resource, $action)) {
        Write-PipelineMessage "Skipped rule $($rule.DisplayName)." -Level Warning
        continue
    }

    $description = New-FixtureDescription -NamePrefix $NamePrefix -FixtureMarker $script:FixtureMarker `
                                          -RunId $runId -ScenarioName $rule.ScenarioName -Enabled $ruleEnabled

    $body    = New-AlertRuleBody -DisplayName $rule.DisplayName -Description $description `
                                 -Query $rule.Query -Enabled $ruleEnabled
    $payload = ConvertTo-Json -InputObject $body -Depth 10

    # A 400 whose body says the query could not be resolved is a propagation
    # race, not a contract error, so it is retried for a bounded window. Any
    # other 400 is a real problem and surfaces immediately with the ARM body
    # intact.
    $attemptDeadline = [datetime]::UtcNow.AddSeconds([math]::Min($TimeoutSeconds, 600))
    $written = $false
    $lastError = $null

    while (-not $written) {
        try {
            Invoke-ArmRequest -Uri $ruleUri -Method PUT -Payload $payload -SuccessCode @(200, 201) | Out-Null
            $written = $true
        }
        catch {
            $lastError = $_.Exception.Message
            $isResolveRace = ($lastError -match 'Failed to resolve') -or ($lastError -match 'SemanticError')

            if ($isResolveRace -and [datetime]::UtcNow -lt $attemptDeadline) {
                Write-PipelineMessage "Rule '$($rule.DisplayName)' cannot resolve its query yet. Retrying in 30s."
                Start-Sleep -Seconds 30
                continue
            }

            break
        }
    }

    if ($written) {
        $state = if ($ruleEnabled) { 'enabled' } else { 'disabled' }
        Write-PipelineMessage "Created $state rule '$($rule.DisplayName)' ($($rule.RuleId))." -Level Success
        $created.Add($resource)
    }
    else {
        Write-PipelineMessage "Failed to create rule '$($rule.DisplayName)': $($lastError.Split([char]10)[0])" -Level Warning
        $failed.Add($resource)
    }
}

#endregion

#region -- Summary -------------------------------------------------------------

Write-PipelineMessage 'Fixture summary' -Level Section
Write-PipelineMessage "  Created : $($created.Count)"
Write-PipelineMessage "  Skipped : $($skipped.Count)"
Write-PipelineMessage "  Failed  : $($failed.Count)"

if ($created.Count -gt 0) {
    Write-PipelineMessage ''
    Write-PipelineMessage 'Now run the review tool and check what it reports:'
    Write-PipelineMessage "  ./Invoke-TableMigrationReview.ps1 -SubscriptionId $resolvedSubscriptionId -ResourceGroupName $ResourceGroupName -WorkspaceName $WorkspaceName"
    Write-PipelineMessage ''
    Write-PipelineMessage 'Expected once transitive resolution works:'
    Write-PipelineMessage "  $($NamePrefix)Direct_CL  one analytics rule (direct)"
    Write-PipelineMessage "  $($NamePrefix)OneHop_CL  one parser, one analytics rule (via the parser), one hunting query (via the parser)"
    Write-PipelineMessage "  $($NamePrefix)TwoHop_CL  two parsers, one analytics rule (via two parsers)"
    Write-PipelineMessage "  $($NamePrefix)Cycle_CL   two parsers that reference each other, one analytics rule"
    Write-PipelineMessage "  $($NamePrefix)Orphan_CL  nothing at all"
    Write-PipelineMessage ''
    Write-PipelineMessage "Tear it down with: -Remove -MigrateBeforeRemove -NamePrefix $NamePrefix"
}

[pscustomobject]@{
    Mode          = 'Create'
    NamePrefix    = $NamePrefix
    FixtureMarker = $script:FixtureMarker
    RunId         = $runId
    WorkspaceName = $WorkspaceName
    ScenarioName  = @($plan.ScenarioName)
    RulesEnabled  = $ruleEnabled
    Created       = $created.ToArray()
    Skipped       = $skipped.ToArray()
    Failed        = $failed.ToArray()
}

#endregion

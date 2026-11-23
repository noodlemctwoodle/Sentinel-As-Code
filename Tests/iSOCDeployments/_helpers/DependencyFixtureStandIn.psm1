#Requires -Version 7.6

<#
.SYNOPSIS
    A stand-in Sentinel workspace for the dependency fixture, which answers
    and changes as the fixture writes.

.DESCRIPTION
    Get-DependencyFixtureStandIn builds the state: built-in and customer
    tables (one named as another prefix's alias would be), a customer parser
    whose alias collides with another prefix's, a customer saved search and
    rule that share the fixture's prefix, a Content Hub rule, and with
    -Existing a fixture the script would have left: marked tables (some still
    classic, some DCR-based; with -UnmarkedOrphan the orphan has no marker
    column), tagged parsers and
    hunting query, a stray tagged saved search, and rules under the derived
    ids.

    Invoke-DependencyFixtureArm answers the ARM calls the way the services
    do: a rule whose query's source does not resolve to a table or a parser
    alias is a 400 'Failed to resolve table or column expression named'
    (with -RaceOnce, every rule's first write is too), and a classic table
    cannot be deleted. Data Collector posts are checked against the
    workspace key and create a classic table with the suffixed columns.
    Every write (Post, SavedPut, RulePut, Delete, Migrate) is recorded in
    Writes, normalised where a run id or a time goes, so the script's
    stand-ins and the module's mocks can be compared.

.NOTES
    File:         Tests/iSOCDeployments/_helpers/DependencyFixtureStandIn.psm1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-StandInRuleId {
    <#
    .SYNOPSIS
        Returns a GUID derived from a prefix and a scenario, so the same scenario always gets the same rule ID.
    .PARAMETER Prefix
        The prefix of the rule.
    .PARAMETER Scenario
        The name of the scenario.
    #>
    param([string] $Prefix, [string] $Scenario)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $hash = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes("Sentinel-As-Code/ClassicToDcr/DependencyFixture|$Prefix|$Scenario"))
    $sha.Dispose()
    ([guid]::new([byte[]]$hash[0..15])).ToString()
}

function Get-DependencyFixtureStandIn {
    <#
    .SYNOPSIS
        Returns the stand-in state of a workspace for the dependency fixture tests, with the switches choosing which odd cases it holds.
    .PARAMETER Existing
        Starts with the fixture resources already deployed.
    .PARAMETER UnmarkedOrphan
        Adds an orphaned resource that carries no marker.
    .PARAMETER NotOnboarded
        Leaves the workspace without Sentinel onboarded.
    .PARAMETER RaceOnce
        Makes one create race with another deployment once.
    #>
    param([switch] $Existing, [switch] $UnmarkedOrphan, [switch] $NotOnboarded, [switch] $RaceOnce)

    $sub = '11111111-2222-3333-4444-555555555555'
    $ws = "/subscriptions/$sub/resourceGroups/rg-sentinel/providers/Microsoft.OperationalInsights/workspaces/law-sentinel"
    $col = { param([string[]] $Names) @($Names | ForEach-Object { [ordered]@{ name = $_; type = $(if ($_ -eq 'TimeGenerated') { 'datetime' } else { 'string' }) } }) }
    $table = { param($Type, $SubType, [string[]] $Columns) [ordered]@{ tableType = $Type; subType = $SubType; columns = (& $col $Columns) } }
    $saved = {
        param($Name, $Category, $Query, $Alias, [switch] $Tagged)
        $p = [ordered]@{ category = $Category; displayName = $Name; query = $Query; version = 2 }
        if ($Alias) { $p.functionAlias = $Alias }
        if ($Tagged) { $p.tags = @([ordered]@{ name = 'SacFixture'; value = 'ClassicToDcr-DependencyFixture' }, [ordered]@{ name = 'SacFixtureRun'; value = 'old-run' }) }
        [ordered]@{ id = "$ws/savedSearches/$Name"; name = $Name; etag = 'W/"1"'; properties = $p }
    }
    $state = [ordered]@{
        SubscriptionId = $sub
        WorkspacePath  = $ws
        WorkspaceName  = 'law-sentinel'
        WorkspaceId    = 'cccccccc-0000-0000-0000-000000000003'
        SharedKey      = [Convert]::ToBase64String([byte[]](10..73))
        Onboarded      = -not $NotOnboarded
        RaceOnce       = [bool]$RaceOnce
        Raced          = @()
        Tables         = [ordered]@{
            'SecurityEvent'   = & $table 'Microsoft' 'Any' 'TimeGenerated', 'EventID'
            'SigninLogs'      = & $table 'Microsoft' 'Any' 'TimeGenerated', 'UserPrincipalName'
            'SecOneHopParser' = & $table 'CustomLog' 'DataCollectionRuleBased' 'TimeGenerated', 'Data_s'
            'TakenDirect_CL'  = & $table 'CustomLog' 'Classic' 'TimeGenerated', 'Other_s'
        }
        Saved          = [ordered]@{
            'cust-parser' = & $saved 'cust-parser' 'Parsers' 'SigninLogs | take 1' 'CollOneHopParser'
            'SacDepNotes' = & $saved 'SacDepNotes' 'General' 'SecurityEvent | take 5' $null
        }
        Rules          = [ordered]@{
            'cust-rule' = [ordered]@{ id = "$ws/providers/Microsoft.SecurityInsights/alertRules/cust-rule"; name = 'cust-rule'; kind = 'Scheduled'; properties = [ordered]@{ displayName = 'SacDep customer rule'; description = 'not a fixture'; query = 'SecurityEvent' } }
            'hub-rule'  = [ordered]@{ id = "$ws/providers/Microsoft.SecurityInsights/alertRules/hub-rule"; name = 'hub-rule'; kind = 'Scheduled'; properties = [ordered]@{ displayName = 'Hub rule'; alertRuleTemplateName = 'tmpl'; description = '[SacFixture:ClassicToDcr-DependencyFixture:x:y]'; query = 'SigninLogs' } }
        }
        Writes         = @()
    }

    if ($Existing) {
        $marker = 'TimeGenerated', 'SourceHost_s', 'Severity_s', 'Scenario_s', 'Message_s', 'SacFixtureMarker_s'
        $state.Tables['SacDepDirect_CL'] = & $table 'CustomLog' 'DataCollectionRuleBased' $marker
        $state.Tables['SacDepOneHop_CL'] = & $table 'CustomLog' 'Classic' $marker
        $state.Tables['SacDepTwoHop_CL'] = & $table 'CustomLog' 'Classic' $marker
        $state.Tables['SacDepCycle_CL'] = & $table 'CustomLog' 'DataCollectionRuleBased' $marker
        $state.Tables['SacDepOrphan_CL'] = if ($UnmarkedOrphan) { & $table 'CustomLog' 'Classic' 'TimeGenerated', 'SourceHost_s' } else { & $table 'CustomLog' 'Classic' $marker }
        foreach ($p in @(
                @('SacDep-OneHopParser', 'SacDepOneHop_CL', 'SacDepOneHopParser'), @('SacDep-InnerParser', 'SacDepTwoHop_CL', 'SacDepInnerParser'),
                @('SacDep-OuterParser', 'SacDepInnerParser', 'SacDepOuterParser'), @('SacDep-CycleA', 'union SacDepCycle_CL, SacDepCycleB', 'SacDepCycleA'),
                @('SacDep-CycleB', 'SacDepCycleA', 'SacDepCycleB'))) {
            $state.Saved[$p[0]] = & $saved $p[0] 'SacDep Fixture' $p[1] $p[2] -Tagged
        }
        $state.Saved['SacDep-Hunt'] = & $saved 'SacDep-Hunt' 'Hunting Queries' 'SacDepOneHopParser | count' $null -Tagged
        $state.Saved['SacDep-OldStray'] = & $saved 'SacDep-OldStray' 'SacDep Fixture' 'SecurityEvent' 'SacDepOldStray' -Tagged
        foreach ($s in 'Direct', 'OneHop', 'TwoHop', 'Cycle') {
            $id = Get-StandInRuleId -Prefix 'SacDep' -Scenario $s
            $state.Rules[$id] = [ordered]@{ id = "$ws/providers/Microsoft.SecurityInsights/alertRules/$id"; name = $id; kind = 'Scheduled'; properties = [ordered]@{ displayName = "SacDep fixture $s"; description = "x`n[SacFixture:ClassicToDcr-DependencyFixture:old-run:$s]"; query = 'SecurityEvent' } }
        }
    }
    $state
}

function Add-DependencyFixtureWrite {
    <#
    .SYNOPSIS
        Appends a write to the Writes list of the stand-in state.
    .PARAMETER State
        The stand-in state table the call reads and changes.
    .PARAMETER Write
        The write to record, added to the Writes list of the state.
    #>
    param($State, [hashtable] $Write)
    $State.Writes = @($State.Writes) + @([pscustomobject]$Write)
}

function ConvertTo-StandInCanonical {
    <#
    .SYNOPSIS
        Returns compressed JSON with the keys of every object sorted, so two values compare whatever order they were built in.
    .PARAMETER Value
        The value to turn into canonical JSON.
    #>
    param($Value)
    $walk = {
        param($Node)
        if ($null -eq $Node) { return $null }
        if ($Node -is [string] -or $Node -is [ValueType]) { return $Node }
        if ($Node -is [System.Collections.IDictionary]) {
            $out = [ordered]@{}
            foreach ($k in @($Node.Keys) | Sort-Object) { $out[$k] = & $walk $Node[$k] }
            return $out
        }
        if ($Node -is [System.Collections.IEnumerable]) { return , @(foreach ($c in $Node) { & $walk $c }) }
        $out = [ordered]@{}
        foreach ($p in @($Node.PSObject.Properties.Name) | Sort-Object) { $out[$p] = & $walk $Node.$p }
        $out
    }
    ConvertTo-Json -InputObject (& $walk $Value) -Depth 30 -Compress
}

function ConvertTo-StandInNormalBody {
    <#
    .SYNOPSIS
        The body with the run id and the removal hint made the same for both sides.
    .PARAMETER Json
        The JSON text of the body.
    #>
    param([string] $Json)
    $o = $Json | ConvertFrom-Json -Depth 30 -AsHashtable
    $props = $o['properties']
    if ($props.Contains('tags')) {
        foreach ($tag in $props['tags']) { if ($tag['name'] -eq 'SacFixtureRun') { $tag['value'] = 'RUN' } }
    }
    if ($props.Contains('description')) {
        $props['description'] = ([string]$props['description']) -replace ':[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}:', ':RUN:' -replace '(?m)^Remove with .*$', 'Remove with X'
    }
    ConvertTo-StandInCanonical $o
}

function Invoke-DependencyFixtureCollector {
    <#
    .SYNOPSIS
        Stand-in for one Data Collector post: checks the URI and the shared key signature, creates the table when it is new, records the post and returns the HTTP status.
    .PARAMETER State
        The stand-in state table the call reads and changes.
    .PARAMETER Uri
        The URI of the request.
    .PARAMETER Headers
        The headers of the request.
    .PARAMETER Body
        The request body.
    #>
    param($State, [string] $Uri, [hashtable] $Headers, [byte[]] $Body)
    if ($Uri -ne "https://$($State.WorkspaceId).ods.opinsights.azure.com/api/logs?api-version=2016-04-01") { return 404 }
    $date = $Headers['x-ms-date']
    $hmac = [System.Security.Cryptography.HMACSHA256]::new([Convert]::FromBase64String($State.SharedKey))
    $expected = "SharedKey $($State.WorkspaceId):" + [Convert]::ToBase64String($hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes("POST`n$($Body.Length)`napplication/json`nx-ms-date:$date`n/api/logs")))
    $hmac.Dispose()
    if ($Headers['Authorization'] -ne $expected) { return 403 }
    $records = @([System.Text.Encoding]::UTF8.GetString($Body) | ConvertFrom-Json -Depth 10 -AsHashtable)
    $table = "$($Headers['Log-Type'])_CL"
    if (-not $State.Tables.Contains($table)) {
        $cols = @([ordered]@{ name = 'TimeGenerated'; type = 'datetime' }) + @($records[0].Keys | Where-Object { $_ -ne $Headers['time-generated-field'] } | Sort-Object | ForEach-Object { [ordered]@{ name = "${_}_s"; type = 'string' } })
        $State.Tables[$table] = [ordered]@{ tableType = 'CustomLog'; subType = 'Classic'; columns = $cols }
    }
    $normal = foreach ($r in $records) {
        $o = [ordered]@{}
        foreach ($k in $r.Keys) { $o[$k] = if ($k -eq 'Timestamp') { 'TIME' } elseif ($k -eq 'SacFixtureMarker') { ($r[$k] -replace '\|.*$', '|RUN') } else { $r[$k] } }
        $o
    }
    Add-DependencyFixtureWrite -State $State -Write @{ Kind = 'Post'; LogType = $Headers['Log-Type']; Records = (ConvertTo-StandInCanonical @($normal)) }
    200
}

function Invoke-DependencyFixtureQuery {
    <#
    .SYNOPSIS
        Answers a take-one log query on a table the state holds, and throws for any other query.
    .PARAMETER State
        The stand-in state table the call reads and changes.
    .PARAMETER Query
        The log query text the stand-in answers.
    #>
    param($State, [string] $Query)
    if ($Query -match '^(\w+) \| take 1$' -and $State.Tables.Contains($Matches[1])) { return [pscustomobject]@{ Results = @() } }
    throw "Failed to resolve table expression named '$Query'"
}

function Invoke-DependencyFixtureArm {
    <#
    .SYNOPSIS
        One ARM call; returns @{ Status; Body }. Body is a JSON string for a PUT.
    .PARAMETER State
        The stand-in state table the call reads and changes.
    .PARAMETER Method
        The HTTP method of the call.
    .PARAMETER Path
        The request path, with any query string.
    .PARAMETER Body
        The request body.
    #>
    param($State, [string] $Method, [string] $Path, [string] $Body)
    $p = ($Path -split '\?')[0]
    $ws = [regex]::Escape($State.WorkspacePath)
    $notFound = @{ Status = 404; Body = [ordered]@{ error = [ordered]@{ code = 'NotFound'; message = 'Not found.' } } }
    $tableBody = { param($Name) $t = $State.Tables[$Name]; [ordered]@{ id = "$($State.WorkspacePath)/tables/$Name"; name = $Name; properties = [ordered]@{ schema = [ordered]@{ name = $Name; tableType = $t.tableType; tableSubType = $t.subType; columns = @($t.columns) } } } }

    if ($p -match "^$ws/providers/Microsoft\.SecurityInsights/onboardingStates/default$") {
        if ($State.Onboarded) { return @{ Status = 200; Body = [ordered]@{ name = 'default'; properties = [ordered]@{} } } }
        return $notFound
    }
    if ($Method -eq 'POST' -and $p -match "^$ws/sharedKeys$") { return @{ Status = 200; Body = [ordered]@{ primarySharedKey = $State.SharedKey; secondarySharedKey = 'second' } } }
    if ($Method -eq 'GET' -and $p -match "^$ws/tables$") { return @{ Status = 200; Body = [ordered]@{ value = @($State.Tables.Keys | ForEach-Object { & $tableBody $_ }) } } }
    if ($Method -eq 'GET' -and $p -match "^$ws/savedSearches$") { return @{ Status = 200; Body = [ordered]@{ value = @($State.Saved.Values) } } }
    if ($Method -eq 'GET' -and $p -match "^$ws/providers/Microsoft\.SecurityInsights/alertRules$") { return @{ Status = 200; Body = [ordered]@{ value = @($State.Rules.Values) } } }

    if ($p -match "^$ws/tables/([^/]+)(/migrate)?$") {
        $name = $Matches[1]
        if (-not $State.Tables.Contains($name)) { return $notFound }
        if ($Method -eq 'GET') { return @{ Status = 200; Body = (& $tableBody $name) } }
        if ($Method -eq 'POST' -and $Matches[2]) { $State.Tables[$name].subType = 'DataCollectionRuleBased'; Add-DependencyFixtureWrite -State $State -Write @{ Kind = 'Migrate'; Table = $name }; return @{ Status = 204; Body = $null } }
        if ($Method -eq 'DELETE') {
            if ($State.Tables[$name].subType -eq 'Classic') { return @{ Status = 400; Body = [ordered]@{ error = [ordered]@{ code = 'BadRequest'; message = 'Changing Classic table by using DataCollectionRuleBased tables api is forbidden' } } } }
            $State.Tables.Remove($name)
            Add-DependencyFixtureWrite -State $State -Write @{ Kind = 'Delete'; Target = "tables/$name" }
            return @{ Status = 202; Body = $null }
        }
    }
    if ($p -match "^$ws/savedSearches/([^/]+)$") {
        $name = $Matches[1]
        if ($Method -eq 'PUT') {
            $o = $Body | ConvertFrom-Json -Depth 30 -AsHashtable
            $State.Saved[$name] = [ordered]@{ id = "$($State.WorkspacePath)/savedSearches/$name"; name = $name; etag = 'W/"2"'; properties = $o['properties'] }
            Add-DependencyFixtureWrite -State $State -Write @{ Kind = 'SavedPut'; Target = $name; Body = (ConvertTo-StandInNormalBody $Body) }
            return @{ Status = 200; Body = $State.Saved[$name] }
        }
        if ($Method -eq 'DELETE') {
            if (-not $State.Saved.Contains($name)) { return $notFound }
            $State.Saved.Remove($name)
            Add-DependencyFixtureWrite -State $State -Write @{ Kind = 'Delete'; Target = "savedSearches/$name" }
            return @{ Status = 200; Body = $null }
        }
    }
    if ($p -match "^$ws/providers/Microsoft\.SecurityInsights/alertRules/([^/]+)$") {
        $id = $Matches[1]
        if ($Method -eq 'PUT') {
            $o = $Body | ConvertFrom-Json -Depth 30 -AsHashtable
            $source = (([string]$o['properties']['query']) -split '\n')[0].Trim()
            $aliases = @($State.Saved.Values | ForEach-Object { if ($_.properties.Contains('functionAlias')) { $_.properties['functionAlias'] } })
            $resolves = $State.Tables.Contains($source) -or ($aliases -contains $source)
            if ($State.RaceOnce -and @($State.Raced) -notcontains $id) { $State.Raced = @($State.Raced) + @($id); $resolves = $false }
            if (-not $resolves) { return @{ Status = 400; Body = [ordered]@{ error = [ordered]@{ code = 'BadRequest'; message = "Failed to run the analytics rule query. One of the tables does not exist. Failed to resolve table or column expression named '$source'" } } } }
            $State.Rules[$id] = [ordered]@{ id = $p; name = $id; kind = $o['kind']; properties = $o['properties'] }
            Add-DependencyFixtureWrite -State $State -Write @{ Kind = 'RulePut'; Target = $id; Body = (ConvertTo-StandInNormalBody $Body) }
            return @{ Status = 201; Body = $State.Rules[$id] }
        }
        if ($Method -eq 'DELETE') {
            if (-not $State.Rules.Contains($id)) { return $notFound }
            $State.Rules.Remove($id)
            Add-DependencyFixtureWrite -State $State -Write @{ Kind = 'Delete'; Target = "alertRules/$id" }
            return @{ Status = 200; Body = $null }
        }
    }
    throw "The stand-in has no answer for $Method $p"
}

Export-ModuleMember -Function Get-DependencyFixtureStandIn, ConvertTo-StandInCanonical, Invoke-DependencyFixtureCollector, Invoke-DependencyFixtureQuery, Invoke-DependencyFixtureArm, Get-StandInRuleId

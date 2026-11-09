#Requires -Version 7.6

<#
.SYNOPSIS
    A stand-in workspace, Data Collector API, token endpoint and Logs
    Ingestion API for the migration rehearsal aids.

.DESCRIPTION
    Get-RehearsalStandIn builds the state: a workspace with its shared key,
    a classic and a DCR-based table, data collection rules (one stream, two
    streams, no endpoint), two applications (one already holding the
    ingestion role) and their secrets.

    The answers check what they are sent the way the services do: a Data
    Collector post must carry a valid SharedKey signature over its date and
    byte length, and creates a classic table with the suffixed columns; a
    token request must name a known client and its secret; an ingestion
    post must carry a token that was issued and records with every column
    the stream declares. Every write (Post, Migrate, Delete, Token, Ingest,
    Grant) is recorded in the state's Writes, in order, so the script's
    stand-ins and the module's mocks can be compared.

.NOTES
    File:         Tests/iSOCDeployments/_helpers/RehearsalStandIn.psm1
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

function Get-RehearsalStandIn {
    param([int[]] $FailBatch = @(), [switch] $FailCollector)

    $sub = '11111111-2222-3333-4444-555555555555'
    $ws = "/subscriptions/$sub/resourceGroups/rg-scratch/providers/Microsoft.OperationalInsights/workspaces/law-scratch"
    $column = { param($Name, $Type) [ordered]@{ name = $Name; type = $Type } }
    $dcr = {
        param($Name, [hashtable] $Streams, [switch] $NoEndpoint)
        $props = [ordered]@{ immutableId = "dcr-$($Name.Replace('-', ''))".PadRight(36, '0').Substring(0, 36) }
        if (-not $NoEndpoint) { $props.endpoints = [ordered]@{ logsIngestion = "https://$Name-x1y2.uksouth-1.ingest.monitor.azure.com" } }
        $props.streamDeclarations = [ordered]@{}
        foreach ($s in $Streams.Keys | Sort-Object) { $props.streamDeclarations[$s] = [ordered]@{ columns = @($Streams[$s]) } }
        $props.destinations = [ordered]@{ logAnalytics = @([ordered]@{ workspaceResourceId = $ws; name = 'workspaceDestination' }) }
        $props.dataFlows = @(foreach ($s in $Streams.Keys | Sort-Object) { [ordered]@{ streams = @($s); destinations = @('workspaceDestination'); transformKql = 'source'; outputStream = $s } })
        [ordered]@{ id = "/subscriptions/$sub/resourceGroups/rg-scratch/providers/Microsoft.Insights/dataCollectionRules/$Name"; name = $Name; kind = 'Direct'; properties = $props }
    }
    $myApp = @(& $column 'TimeGenerated' 'datetime'; & $column 'Message_s' 'string'; & $column 'Count_d' 'real'; & $column 'Flag_b' 'boolean'; & $column 'Level_i' 'int'; & $column 'Big_l' 'long'; & $column 'Props_d' 'dynamic')
    [ordered]@{
        SubscriptionId = $sub
        WorkspacePath  = $ws
        WorkspaceName  = 'law-scratch'
        WorkspaceId    = 'cccccccc-0000-0000-0000-000000000002'
        SharedKey      = [Convert]::ToBase64String([byte[]](1..64))
        Tables         = [ordered]@{
            'Old_CL'  = [ordered]@{ subType = 'Classic'; columns = @(& $column 'TimeGenerated' 'datetime') }
            'Done_CL' = [ordered]@{ subType = 'DataCollectionRuleBased'; columns = @(& $column 'TimeGenerated' 'datetime') }
        }
        Rows           = [ordered]@{}
        Dcrs           = [ordered]@{
            'dcr-myapp' = & $dcr 'dcr-myapp' @{ 'Custom-MyApp_CL' = $myApp }
            'dcr-two'   = & $dcr 'dcr-two' @{ 'Custom-One_CL' = @(& $column 'TimeGenerated' 'datetime'; & $column 'Note_s' 'string'); 'Custom-Two_CL' = @(& $column 'TimeGenerated' 'datetime'; & $column 'Value_d' 'real') }
            'dcr-bare'  = & $dcr 'dcr-bare' @{ 'Custom-Bare_CL' = @(& $column 'TimeGenerated' 'datetime') } -NoEndpoint
        }
        Apps           = [ordered]@{ 'aaaaaaaa-1111-2222-3333-444444444444' = 'sp-object-1'; 'bbbbbbbb-1111-2222-3333-444444444444' = 'sp-object-2' }
        Secrets        = [ordered]@{ 'aaaaaaaa-1111-2222-3333-444444444444' = 'secret-a'; 'bbbbbbbb-1111-2222-3333-444444444444' = 'secret-b' }
        Assignments    = @([ordered]@{ PrincipalId = 'sp-object-2'; Role = 'Monitoring Metrics Publisher'; Scope = "/subscriptions/$sub/resourceGroups/rg-scratch" })
        Tokens         = @()
        IngestCount    = 0
        FailBatch      = @($FailBatch)
        FailCollector  = [bool]$FailCollector
        Writes         = @()
    }
}

function Add-RehearsalWrite {
    param($State, [hashtable] $Write)
    $State.Writes = @($State.Writes) + @([pscustomobject]$Write)
}

function ConvertTo-RehearsalCanonical {
    <# JSON with every object's keys sorted, so hashtable order cannot differ. #>
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

function Invoke-RehearsalCollector {
    <# One Data Collector post. Returns the HTTP status. #>
    param($State, [string] $Uri, [hashtable] $Headers, [byte[]] $Body)

    if ($Uri -ne "https://$($State.WorkspaceId).ods.opinsights.azure.com/api/logs?api-version=2016-04-01") { return 404 }
    if ($State.FailCollector) { return 500 }
    $date = $Headers['x-ms-date']
    $stringToHash = "POST`n$($Body.Length)`napplication/json`nx-ms-date:$date`n/api/logs"
    $hmac = [System.Security.Cryptography.HMACSHA256]::new([Convert]::FromBase64String($State.SharedKey))
    $expected = "SharedKey $($State.WorkspaceId):" + [Convert]::ToBase64String($hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($stringToHash)))
    $hmac.Dispose()
    if ($Headers['Authorization'] -ne $expected) { return 403 }

    $records = @([System.Text.Encoding]::UTF8.GetString($Body) | ConvertFrom-Json -Depth 10)
    $logType = $Headers['Log-Type']
    $table = "${logType}_CL"
    if (-not $State.Tables.Contains($table)) {
        $suffix = @{ 'String' = '_s'; 'Double' = '_d'; 'Boolean' = '_b' }
        $cols = @([ordered]@{ name = 'TimeGenerated'; type = 'datetime' })
        foreach ($p in $records[0].PSObject.Properties) {
            if ($p.Name -eq $Headers['time-generated-field']) { continue }
            $kind = if ($p.Value -is [bool]) { 'Boolean' } elseif ($p.Value -is [double] -or $p.Value -is [int] -or $p.Value -is [long] -or $p.Value -is [decimal]) { 'Double' } else { 'String' }
            $s = if ($kind -eq 'String' -and [string]$p.Value -match '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$') { '_g' } else { $suffix[$kind] }
            $cols += [ordered]@{ name = "$($p.Name)$s"; type = 'string' }
        }
        $State.Tables[$table] = [ordered]@{ subType = 'Classic'; columns = $cols }
    }
    $normal = foreach ($r in $records) {
        $o = [ordered]@{}
        foreach ($p in $r.PSObject.Properties) { $o[$p.Name] = if ($p.Name -eq 'Timestamp') { 'TIME' } elseif ($p.Name -eq 'EventId') { 'GUID' } else { $p.Value } }
        $o
    }
    Add-RehearsalWrite -State $State -Write @{ Kind = 'Post'; LogType = $logType; TimeField = $Headers['time-generated-field']; Records = (ConvertTo-RehearsalCanonical @($normal)) }
    200
}

function Invoke-RehearsalArm {
    <# One ARM call; returns @{ Status; Body }. #>
    param($State, [string] $Method, [string] $Path)
    $p = ($Path -split '\?')[0]
    $ws = [regex]::Escape($State.WorkspacePath)
    if ($Method -eq 'POST' -and $p -match "^$ws/sharedKeys$") { return @{ Status = 200; Body = [ordered]@{ primarySharedKey = $State.SharedKey; secondarySharedKey = 'second' } } }
    if ($Method -eq 'GET' -and $p -match "^$ws$") { return @{ Status = 200; Body = [ordered]@{ id = $State.WorkspacePath; name = $State.WorkspaceName; location = 'uksouth'; properties = [ordered]@{ customerId = $State.WorkspaceId } } } }
    if ($p -match "^$ws/tables/([^/]+)(/migrate)?$") {
        $name = $Matches[1]
        $t = if ($State.Tables.Contains($name)) { $State.Tables[$name] } else { $null }
        if (-not $t) { return @{ Status = 404; Body = [ordered]@{ error = [ordered]@{ code = 'ResourceNotFound' } } } }
        if ($Method -eq 'GET') { return @{ Status = 200; Body = [ordered]@{ id = "$($State.WorkspacePath)/tables/$name"; name = $name; properties = [ordered]@{ schema = [ordered]@{ name = $name; tableSubType = $t.subType; columns = @($t.columns) } } } } }
        if ($Method -eq 'POST' -and $Matches[2]) { $t.subType = 'DataCollectionRuleBased'; Add-RehearsalWrite -State $State -Write @{ Kind = 'Migrate'; Table = $name }; return @{ Status = 204; Body = $null } }
        if ($Method -eq 'DELETE') {
            if ($t.subType -eq 'Classic') { return @{ Status = 400; Body = [ordered]@{ error = [ordered]@{ code = 'BadRequest'; message = 'Changing Classic table by using DataCollectionRuleBased tables api is forbidden' } } } }
            $State.Tables.Remove($name)
            Add-RehearsalWrite -State $State -Write @{ Kind = 'Delete'; Table = $name }
            return @{ Status = 202; Body = $null }
        }
    }
    if ($Method -eq 'GET' -and $p -match '/providers/Microsoft\.Insights/dataCollectionRules/([^/]+)$') {
        if (-not $State.Dcrs.Contains($Matches[1])) { return @{ Status = 404; Body = [ordered]@{ error = [ordered]@{ code = 'ResourceNotFound' } } } }
        return @{ Status = 200; Body = $State.Dcrs[$Matches[1]] }
    }
    throw "The stand-in has no answer for $Method $p"
}

function Invoke-RehearsalToken {
    <# One token request. Returns @{ Status; Body }. #>
    param($State, [string] $Uri, [hashtable] $Form)
    if ($Uri -notmatch '^https://login\.microsoftonline\.com/([^/]+)/oauth2/v2\.0/token$') { return @{ Status = 404; Body = @{ error = 'not_found' } } }
    $tenant = $Matches[1]
    $ok = $Form['grant_type'] -eq 'client_credentials' -and $Form['scope'] -eq 'https://monitor.azure.com/.default' -and $State.Secrets.Contains([string]$Form['client_id']) -and $State.Secrets[[string]$Form['client_id']] -eq $Form['client_secret']
    if (-not $ok) { return @{ Status = 401; Body = [ordered]@{ error = 'invalid_client'; error_description = 'AADSTS7000215: Invalid client secret provided.' } } }
    $token = "token-$($State.Tokens.Count + 1)"
    $State.Tokens = @($State.Tokens) + @($token)
    Add-RehearsalWrite -State $State -Write @{ Kind = 'Token'; Tenant = $tenant; Client = $Form['client_id']; Scope = $Form['scope'] }
    @{ Status = 200; Body = [ordered]@{ token_type = 'Bearer'; expires_in = 3599; access_token = $token } }
}

function Invoke-RehearsalIngest {
    <# One Logs Ingestion post. Returns @{ Status; Content }. #>
    param($State, [string] $Uri, [hashtable] $Headers, [byte[]] $Body)
    $dcr = @($State.Dcrs.Values | Where-Object { $_.properties.Contains('endpoints') -and $Uri.StartsWith("$($_.properties.endpoints.logsIngestion)/dataCollectionRules/$($_.properties.immutableId)/streams/") }) | Select-Object -First 1
    if (-not $dcr -or $Uri -notmatch '/streams/([^/?]+)\?api-version=2023-01-01$') { return @{ Status = 404; Content = '{"error":"not found"}' } }
    $stream = $Matches[1]
    if (@($State.Tokens) -notcontains (($Headers['Authorization']) -replace '^Bearer ', '')) { return @{ Status = 401; Content = '{"error":{"code":"InvalidToken"}}' } }
    $State.IngestCount = $State.IngestCount + 1
    if (@($State.FailBatch) -contains $State.IngestCount) { return @{ Status = 503; Content = "{`"error`":{`"code`":`"ServiceUnavailable`"}}`nmore" } }
    $declared = @($dcr.properties.streamDeclarations[$stream].columns | ForEach-Object { $_.name })
    $records = @([System.Text.Encoding]::UTF8.GetString($Body) | ConvertFrom-Json -Depth 10)
    foreach ($r in $records) {
        $missing = @($declared | Where-Object { -not $r.PSObject.Properties[$_] })
        if ($missing) { return @{ Status = 400; Content = "{`"error`":`"missing $($missing -join ',')`"}" } }
    }
    $table = $stream -replace '^Custom-', ''
    $State.Rows[$table] = @($(if ($State.Rows.Contains($table)) { $State.Rows[$table] } else { @() })) + @($records)
    $normal = foreach ($r in $records) {
        $o = [ordered]@{}
        foreach ($p in $r.PSObject.Properties) {
            $v = $p.Value
            if ($v -is [datetime] -or ($v -is [string] -and $v -match '^\d{4}-\d{2}-\d{2}T')) { $v = 'TIME' }
            elseif ($v -is [string]) { $v = $v -replace '[0-9a-f]{12}', 'RUN' }
            elseif ($v -is [psobject] -and $v.PSObject.Properties['runId']) { $v = [ordered]@{ index = $v.index; runId = 'RUN' } }
            $o[$p.Name] = $v
        }
        $o
    }
    Add-RehearsalWrite -State $State -Write @{ Kind = 'Ingest'; Stream = $stream; Records = (ConvertTo-RehearsalCanonical @($normal)) }
    @{ Status = 204; Content = '' }
}

function Invoke-RehearsalQuery {
    param($State, [string] $Query)
    if ($Query -match "^(\w+) \| where (\w+) has '([0-9a-f]{12})' \| count$") {
        $rows = @($(if ($State.Rows.Contains($Matches[1])) { $State.Rows[$Matches[1]] } else { @() }))
        $column = $Matches[2]
        $run = $Matches[3]
        $count = @($rows | Where-Object { $_.PSObject.Properties[$column] -and ([string]$_.$column).Contains($run) }).Count
        return [pscustomobject]@{ Results = @([pscustomobject]@{ Count = [string]$count }) }
    }
    throw "The stand-in cannot run $Query"
}

function Get-RehearsalAssignment {
    param($State, [string] $PrincipalId, [string] $Scope)
    foreach ($a in @($State.Assignments)) {
        if ($a.PrincipalId -ne $PrincipalId) { continue }
        if ($Scope -and -not ($Scope -eq $a.Scope -or $Scope.StartsWith("$($a.Scope)/", [System.StringComparison]::OrdinalIgnoreCase))) { continue }
        $a
    }
}

function Add-RehearsalAssignment {
    param($State, [string] $PrincipalId, [string] $Role, [string] $Scope)
    $State.Assignments = @($State.Assignments) + @([ordered]@{ PrincipalId = $PrincipalId; Role = $Role; Scope = $Scope })
    Add-RehearsalWrite -State $State -Write @{ Kind = 'Grant'; PrincipalId = $PrincipalId; Role = $Role; Scope = $Scope }
}

Export-ModuleMember -Function Get-RehearsalStandIn, ConvertTo-RehearsalCanonical, Invoke-RehearsalCollector, Invoke-RehearsalArm, Invoke-RehearsalToken, Invoke-RehearsalIngest, Invoke-RehearsalQuery, Get-RehearsalAssignment, Add-RehearsalAssignment

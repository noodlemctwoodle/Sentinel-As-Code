#Requires -Version 7.2

<#
.SYNOPSIS
    A stand-in workspace for the classic table migration, whose tables,
    rules and role assignments change as the run writes.

.DESCRIPTION
    Get-ClassicMigrationStandIn builds the state: classic, DCR-based,
    unreadable and platform tables with columns that are reserved, hidden,
    underscore-led, guid and of an unknown type; row counts (one that cannot
    be counted) and Usage volume; a deployment that fails with its
    operation's message; an application id, a user and a principal that
    already holds the ingestion role, and one refused.

    The Invoke-StandIn* functions answer the reads and record the writes
    (Migrate, Deploy, Grant) in the state's Writes, in order. The script's
    stand-in Az cmdlets and the module's mocked REST client, log query and
    deployment all call them, so both read and change one tenant.

.NOTES
    File:         Tests/iSOCDeployments/_helpers/ClassicMigrationStandIn.psm1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.0
    Last Updated: 2026-11-04
    Requires:     PowerShell 7.2+
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ClassicMigrationStandIn {
    param([switch] $UsageFails)

    $sub = '11111111-2222-3333-4444-555555555555'
    $column = { param($Name, $Type, [switch] $Hidden) $c = [ordered]@{ name = $Name; type = $Type }; if ($Hidden) { $c.isHidden = $true }; $c }
    [ordered]@{
        SubscriptionId = $sub
        ResourceGroup  = 'rg-sentinel'
        WorkspaceName  = 'law-sentinel'
        WorkspaceId    = 'cccccccc-0000-0000-0000-000000000001'
        WorkspacePath  = "/subscriptions/$sub/resourceGroups/rg-sentinel/providers/Microsoft.OperationalInsights/workspaces/law-sentinel"
        Location       = 'uksouth'
        UsageFails     = [bool]$UsageFails
        Tables         = [ordered]@{
            'MyApp_CL'         = [ordered]@{ subType = 'Classic'; plan = 'Analytics'; columns = @(
                    & $column 'TimeGenerated' 'dateTime'
                    & $column 'Message_s' 'string'
                    & $column 'EventId_g' 'guid'
                    & $column 'Count_d' 'real'
                    & $column 'Flag_b' 'boolean'
                    & $column 'Props_d' 'dynamic'
                    & $column '_ResourceId_s' 'string'
                    & $column 'TenantId' 'string'
                    & $column 'Computer' 'string'
                    & $column 'Secret_s' 'string' -Hidden
                )
            }
            'Second_CL'        = [ordered]@{ subType = 'Classic'; plan = 'Basic'; columns = @(& $column 'TimeGenerated' 'dateTime'; & $column 'Value_s' 'string') }
            'Ready_CL'         = [ordered]@{ subType = 'DataCollectionRuleBased'; plan = 'Analytics'; columns = @(& $column 'TimeGenerated' 'dateTime'; & $column 'RawData' 'string'; & $column 'Id_g' 'guid') }
            'Odd_CL'           = [ordered]@{ subType = 'Classic'; plan = 'Analytics'; columns = @(& $column 'Weird_x' 'hyperloglog'; & $column 'Level_i' 'int'; & $column 'Big_l' 'long') }
            'Unknown_CL'       = [ordered]@{ subType = 'Classic'; plan = 'Analytics'; columns = @(& $column 'TimeGenerated' 'dateTime'; & $column 'FilePath' 'string') }
            'Broken_CL'        = [ordered]@{ subType = 'Classic'; plan = 'Analytics'; unreadable = $true; columns = @() }
            'AzureDiagnostics' = [ordered]@{ subType = 'Classic'; plan = 'Analytics'; columns = @(& $column 'TimeGenerated' 'dateTime') }
            'SecurityEvent'    = [ordered]@{ subType = 'Any'; plan = 'Analytics'; columns = @(& $column 'TimeGenerated' 'dateTime') }
        }
        Rows           = [ordered]@{ 'MyApp_CL' = 120; 'Second_CL' = 0; 'Ready_CL' = 5; 'Odd_CL' = 3 }
        RowsFail       = @('Unknown_CL')
        Usage          = [ordered]@{ 'MyApp_CL' = 0.5; 'Odd_CL' = 0.0125; 'SecurityEvent' = 3.2 }
        DeployFails    = @('dcr-odd')
        Dcrs           = [ordered]@{}
        Apps           = [ordered]@{ 'aaaaaaaa-1111-2222-3333-444444444444' = 'sp-object-1' }
        Users          = @('user-object-1', 'held-object-1', 'deny-object-1')
        Denied         = @('deny-object-1')
        Assignments    = @(
            [ordered]@{ PrincipalId = 'held-object-1'; Role = 'Monitoring Metrics Publisher'; Scope = "/subscriptions/$sub/resourceGroups/rg-sentinel" }
        )
        Writes         = @()
    }
}

function Add-StandInWrite {
    param($State, [hashtable] $Write)
    $State.Writes = @($State.Writes) + @([pscustomobject]$Write)
}

function Get-StandInTableBody {
    param($State, [string] $Name)
    $t = $State.Tables[$Name]
    if (-not $t) { return $null }
    $schema = [ordered]@{ name = $Name; tableSubType = $t.subType; tableType = if ($Name -like '*_CL') { 'CustomLog' } else { 'Microsoft' }; columns = @($t.columns) }
    [ordered]@{ id = "$($State.WorkspacePath)/tables/$Name"; name = $Name; properties = [ordered]@{ plan = $t.plan; retentionInDays = 30; schema = $schema } }
}

function Invoke-StandInArm {
    <# One ARM call; returns @{ Status; Body } with Body a JSON-ready object. #>
    param($State, [string] $Method, [string] $Path)

    $p = ($Path -split '\?')[0]
    $ws = [regex]::Escape($State.WorkspacePath)
    if ($Method -eq 'GET' -and $p -match "^$ws/tables$") {
        return @{ Status = 200; Body = [ordered]@{ value = @($State.Tables.Keys | ForEach-Object { Get-StandInTableBody -State $State -Name $_ }) } }
    }
    if ($Method -eq 'GET' -and $p -match "^$ws/tables/([^/]+)$") {
        $name = $Matches[1]
        $t = $State.Tables[$name]
        if (-not $t -or $t.Contains('unreadable')) { return @{ Status = 404; Body = [ordered]@{ error = [ordered]@{ code = 'ResourceNotFound'; message = "The table $name was not found." } } } }
        return @{ Status = 200; Body = (Get-StandInTableBody -State $State -Name $name) }
    }
    if ($Method -eq 'POST' -and $p -match "^$ws/tables/([^/]+)/migrate$") {
        Invoke-StandInMigrate -State $State -Table $Matches[1]
        return @{ Status = 204; Body = $null }
    }
    if ($Method -eq 'GET' -and $p -match '/providers/Microsoft\.Insights/dataCollectionRules/([^/]+)$') {
        $d = $State.Dcrs[$Matches[1]]
        if (-not $d) { return @{ Status = 404; Body = [ordered]@{ error = [ordered]@{ code = 'ResourceNotFound' } } } }
        $props = [ordered]@{ immutableId = $d.immutableId }
        if ($d.endpoint) { $props.endpoints = [ordered]@{ logsIngestion = $d.endpoint } }
        return @{ Status = 200; Body = [ordered]@{ id = $p; name = $Matches[1]; properties = $props } }
    }
    if ($Method -eq 'GET' -and $p -match '/deployments/([^/]+)/operations$') {
        return @{ Status = 200; Body = [ordered]@{ value = @(Get-StandInDeploymentOperation -State $State -DeploymentName $Matches[1]) } }
    }
    throw "The stand-in has no answer for $Method $p"
}

function Invoke-StandInMigrate {
    param($State, [string] $Table)
    $State.Tables[$Table].subType = 'DataCollectionRuleBased'
    Add-StandInWrite -State $State -Write @{ Kind = 'Migrate'; Table = $Table }
}

function Invoke-StandInLogQuery {
    param($State, [string] $Query)
    if ($Query -match '^\s*Usage') {
        if ($State.UsageFails) { throw 'Forbidden: the caller cannot read Usage.' }
        return [pscustomobject]@{ Results = @($State.Usage.Keys | ForEach-Object { [pscustomobject]@{ DataType = $_; GB = [string]$State.Usage[$_] } }) }
    }
    if ($Query -match '^(\w+) \| where TimeGenerated > ago\((\d+)d\) \| count$') {
        $name = $Matches[1]
        if ($State.RowsFail -contains $name) { throw "Failed to resolve table expression named '$name'" }
        $count = if ($State.Rows.Contains($name)) { $State.Rows[$name] } else { 0 }
        return [pscustomobject]@{ Results = @([pscustomobject]@{ Count = [string]$count }) }
    }
    throw "The stand-in cannot run $Query"
}

function Invoke-StandInDeploy {
    param($State, [string] $Name, [string] $ResourceGroup, [string] $TemplateFile)
    $template = Get-Content -LiteralPath $TemplateFile -Raw
    $dcrName = ($template | ConvertFrom-Json -Depth 30).resources[0].name
    $kind = ($template | ConvertFrom-Json -Depth 30).resources[0].kind
    Add-StandInWrite -State $State -Write @{ Kind = 'Deploy'; ResourceGroup = $ResourceGroup; Name = ($Name -replace '-\d{14}$', ''); Template = $template }
    if ($State.DeployFails -contains $dcrName) {
        $State["Failed-$Name"] = $true
        throw "The deployment '$Name' failed with 1 error(s). Show error details for more information."
    }
    $State.Dcrs[$dcrName] = [ordered]@{
        immutableId = "dcr-$(($dcrName -replace '[^a-z0-9]', '').PadRight(32, '0').Substring(0, 32))"
        endpoint    = if ($kind -eq 'Direct') { "https://$dcrName-abcd.uksouth-1.ingest.monitor.azure.com" } else { $null }
    }
    [pscustomobject]@{ DeploymentName = $Name; ProvisioningState = 'Succeeded' }
}

function Get-StandInDeploymentOperation {
    param($State, [string] $DeploymentName)
    if (-not $State.Contains("Failed-$DeploymentName")) { return }
    [ordered]@{ properties = [ordered]@{ provisioningState = 'Failed'; statusMessage = [ordered]@{ status = 'Failed'; error = [ordered]@{ code = 'InvalidOutputTable'; message = 'Table for output stream Custom-Odd_CL is not available.' } } } }
    [ordered]@{ properties = [ordered]@{ provisioningState = 'Succeeded'; statusMessage = 'fine' } }
}

function Resolve-StandInApp {
    param($State, [string] $AppId)
    if ($State.Apps.Contains($AppId)) { return $State.Apps[$AppId] }
    $null
}

function Get-StandInAssignment {
    param($State, [string] $PrincipalId, [string] $Scope)
    foreach ($a in @($State.Assignments)) {
        if ($a.PrincipalId -ne $PrincipalId) { continue }
        if ($Scope -and -not ($Scope -eq $a.Scope -or $Scope.StartsWith("$($a.Scope)/", [System.StringComparison]::OrdinalIgnoreCase))) { continue }
        $a
    }
}

function Add-StandInAssignment {
    param($State, [string] $PrincipalId, [string] $Role, [string] $Scope)
    if ($State.Denied -contains $PrincipalId) { throw "The client does not have authorization to perform action 'Microsoft.Authorization/roleAssignments/write' over scope '$Scope'." }
    $State.Assignments = @($State.Assignments) + @([ordered]@{ PrincipalId = $PrincipalId; Role = $Role; Scope = $Scope })
    Add-StandInWrite -State $State -Write @{ Kind = 'Grant'; PrincipalId = $PrincipalId; Role = $Role; Scope = $Scope }
}

Export-ModuleMember -Function Get-ClassicMigrationStandIn, Invoke-StandInArm, Invoke-StandInMigrate, Invoke-StandInLogQuery, Invoke-StandInDeploy, Get-StandInDeploymentOperation, Resolve-StandInApp, Get-StandInAssignment, Add-StandInAssignment

#Requires -Version 7.6

<#
.SYNOPSIS
    A stand-in workspace for New-iSOCDcrFromSchema and New-DcrFromSchema.ps1,
    whose tables, rules and role assignments change as the run writes.

.DESCRIPTION
    Get-DcrFromSchemaStandIn builds the state: a DCR-based table with a column
    the schema leaves out, a classic table, a table whose column type differs,
    one that cannot be read (403) and one whose answer has no schema; two
    resource groups; a rule whose template fails validation with nested
    details and one whose deployment fails with its operation's message; an
    application id, a user, a principal that already holds the ingestion role
    and one refused.

    The Invoke-DcrFromSchema* functions answer the reads and record the
    validations and writes (Validate, Deploy, Grant) in the state's Writes, in
    order. The script's stand-in Az cmdlets and the module's mocked REST
    client and deployment wrappers all call them, so both read and change one
    tenant.

.NOTES
    File:         Tests/iSOCDeployments/_helpers/DcrFromSchemaStandIn.psm1
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

function Get-DcrFromSchemaStandIn {
    param([switch] $NoEndpoint)

    $sub = '11111111-2222-3333-4444-555555555555'
    $column = { param($Name, $Type) [ordered]@{ name = $Name; type = $Type } }
    [ordered]@{
        SubscriptionId  = $sub
        ResourceGroup   = 'rg-sentinel'
        WorkspaceName   = 'law-sentinel'
        WorkspaceId     = 'cccccccc-0000-0000-0000-000000000001'
        WorkspacePath   = "/subscriptions/$sub/resourceGroups/rg-sentinel/providers/Microsoft.OperationalInsights/workspaces/law-sentinel"
        Location        = 'uksouth'
        ResourceGroups  = @('rg-sentinel', 'rg-dcr')
        NoEndpoint      = [bool]$NoEndpoint
        Tables          = [ordered]@{
            'Existing_CL'  = [ordered]@{ subType = 'DataCollectionRuleBased'; columns = @(& $column 'TimeGenerated' 'dateTime'; & $column 'AlertId' 'string'; & $column 'LiveOnly' 'string'; & $column '_Internal' 'string') }
            'Legacy_CL'    = [ordered]@{ subType = 'Classic'; columns = @(& $column 'TimeGenerated' 'dateTime'; & $column 'Message_s' 'string') }
            'Typed_CL'     = [ordered]@{ subType = 'DataCollectionRuleBased'; columns = @(& $column 'TimeGenerated' 'dateTime'; & $column 'AlertId' 'int') }
            'Broken_CL'    = [ordered]@{ forbidden = $true }
            'Shapeless_CL' = [ordered]@{ shapeless = $true }
        }
        ValidationFails = @('dcr-rejected')
        DeployFails     = @('dcr-failing')
        Dcrs            = [ordered]@{}
        Apps            = [ordered]@{ 'aaaaaaaa-1111-2222-3333-444444444444' = 'sp-object-1' }
        Users           = @('user-object-1', 'held-object-1', 'deny-object-1')
        Denied          = @('deny-object-1')
        Assignments     = @(
            [ordered]@{ PrincipalId = 'held-object-1'; Role = 'Monitoring Metrics Publisher'; Scope = "/subscriptions/$sub/resourceGroups/rg-sentinel" }
        )
        Writes          = @()
    }
}

function Add-DcrFromSchemaWrite {
    param($State, [hashtable] $Write)
    $State.Writes = @($State.Writes) + @([pscustomobject]$Write)
}

function Invoke-DcrFromSchemaArm {
    <# One ARM read; returns @{ Status; Body } with Body a JSON-ready object. #>
    param($State, [string] $Method, [string] $Path)

    $p = ($Path -split '\?')[0]
    $ws = [regex]::Escape($State.WorkspacePath)
    $notFound = @{ Status = 404; Body = [ordered]@{ error = [ordered]@{ code = 'ResourceNotFound'; message = "The resource $p was not found." } } }

    if ($Method -eq 'GET' -and $p -match "^$ws/tables/([^/]+)$") {
        $name = $Matches[1]
        if (-not $State.Tables.Contains($name)) { return $notFound }
        $t = $State.Tables[$name]
        if ($t.Contains('forbidden')) { return @{ Status = 403; Body = [ordered]@{ error = [ordered]@{ code = 'AuthorizationFailed'; message = "The client does not have authorization to read table $name." } } } }
        if ($t.Contains('shapeless')) { return @{ Status = 200; Body = [ordered]@{ id = $p; name = $name } } }
        $schema = [ordered]@{ name = $name; tableSubType = $t.subType; columns = @($t.columns) }
        return @{ Status = 200; Body = [ordered]@{ id = $p; name = $name; properties = [ordered]@{ plan = 'Analytics'; schema = $schema } } }
    }
    if ($Method -eq 'GET' -and $p -match "^/subscriptions/$($State.SubscriptionId)/resourceGroups/([^/]+)$") {
        if ($State.ResourceGroups -notcontains $Matches[1]) { return $notFound }
        return @{ Status = 200; Body = [ordered]@{ id = $p; name = $Matches[1]; location = $State.Location } }
    }
    if ($Method -eq 'GET' -and $p -match '/providers/Microsoft\.Insights/dataCollectionRules/([^/]+)$') {
        if (-not $State.Dcrs.Contains($Matches[1])) { return $notFound }
        $d = $State.Dcrs[$Matches[1]]
        $props = [ordered]@{ immutableId = $d.immutableId }
        if ($d.endpoint) { $props.endpoints = [ordered]@{ logsIngestion = $d.endpoint } }
        return @{ Status = 200; Body = [ordered]@{ id = $p; name = $Matches[1]; kind = 'Direct'; properties = $props } }
    }
    if ($Method -eq 'GET' -and $p -match '/deployments/([^/]+)/operations$') {
        return @{ Status = 200; Body = [ordered]@{ value = @(Get-DcrFromSchemaDeploymentOperation -State $State -DeploymentName $Matches[1]) } }
    }
    throw "The stand-in has no answer for $Method $p"
}

function Get-DcrFromSchemaTemplateResource {
    param([string] $TemplateFile)
    $template = Get-Content -LiteralPath $TemplateFile -Raw
    [pscustomobject]@{ Text = $template; Resource = ($template | ConvertFrom-Json -Depth 30).resources[0] }
}

function Invoke-DcrFromSchemaValidate {
    <# Test-AzResourceGroupDeployment: nothing when valid, else its error list as one object. #>
    param($State, [string] $ResourceGroup, [string] $TemplateFile)

    $t = Get-DcrFromSchemaTemplateResource -TemplateFile $TemplateFile
    Add-DcrFromSchemaWrite -State $State -Write @{ Kind = 'Validate'; ResourceGroup = $ResourceGroup; Resource = [string]$t.Resource.name }
    $short = ([string]$t.Resource.name -split '/')[-1]
    if ($State.ValidationFails -notcontains $short) { return }

    $list = [System.Collections.Generic.List[object]]::new()
    $list.Add([pscustomobject]@{
            Code    = 'InvalidTemplateDeployment'
            Message = "The template deployment '$short' is not valid according to the validation procedure. See inner errors for details."
            Target  = $null
            Details = @([pscustomobject]@{ Code = 'InvalidProperty'; Message = "'Description' length should be 256 characters or less."; Target = 'Properties.Description'; Details = @() })
        })
    , $list
}

function Invoke-DcrFromSchemaDeploy {
    param($State, [string] $Name, [string] $ResourceGroup, [string] $TemplateFile)

    $t = Get-DcrFromSchemaTemplateResource -TemplateFile $TemplateFile
    Add-DcrFromSchemaWrite -State $State -Write @{ Kind = 'Deploy'; ResourceGroup = $ResourceGroup; Name = ($Name -replace '-\d{14}$', ''); Template = $t.Text }
    $short = ([string]$t.Resource.name -split '/')[-1]
    if ($State.DeployFails -contains $short) {
        $State["Failed-$Name"] = $true
        throw "The deployment '$Name' failed with 1 error(s). Show error details for more information."
    }
    if ($t.Resource.type -eq 'Microsoft.OperationalInsights/workspaces/tables') {
        $State.Tables[$short] = [ordered]@{ subType = 'DataCollectionRuleBased'; columns = @($t.Resource.properties.schema.columns | ForEach-Object { [ordered]@{ name = $_.name; type = $_.type } }) }
    }
    else {
        $State.Dcrs[$short] = [ordered]@{
            immutableId = "dcr-$(($short -replace '[^a-z0-9]', '').PadRight(32, '0').Substring(0, 32))"
            endpoint    = if ($State.NoEndpoint) { $null } else { "https://$short-abcd.uksouth-1.ingest.monitor.azure.com" }
        }
    }
    [pscustomobject]@{ DeploymentName = $Name; ProvisioningState = 'Succeeded' }
}

function Get-DcrFromSchemaDeploymentOperation {
    param($State, [string] $DeploymentName)
    if (-not $State.Contains("Failed-$DeploymentName")) { return }
    [ordered]@{ properties = [ordered]@{ provisioningState = 'Failed'; statusMessage = [ordered]@{ status = 'Failed'; error = [ordered]@{ code = 'InvalidOutputTable'; message = 'Table for output stream Custom-Failing_CL is not available.' } } } }
    [ordered]@{ properties = [ordered]@{ provisioningState = 'Succeeded'; statusMessage = 'fine' } }
}

function Resolve-DcrFromSchemaApp {
    param($State, [string] $AppId)
    if ($State.Apps.Contains($AppId)) { return $State.Apps[$AppId] }
    $null
}

function Get-DcrFromSchemaAssignment {
    param($State, [string] $PrincipalId, [string] $Scope)
    foreach ($a in @($State.Assignments)) {
        if ($a.PrincipalId -ne $PrincipalId) { continue }
        if ($Scope -and -not ($Scope -eq $a.Scope -or $Scope.StartsWith("$($a.Scope)/", [System.StringComparison]::OrdinalIgnoreCase))) { continue }
        $a
    }
}

function Add-DcrFromSchemaAssignment {
    param($State, [string] $PrincipalId, [string] $Role, [string] $Scope)
    if ($State.Denied -contains $PrincipalId) { throw "The client does not have authorization to perform action 'Microsoft.Authorization/roleAssignments/write' over scope '$Scope'." }
    $State.Assignments = @($State.Assignments) + @([ordered]@{ PrincipalId = $PrincipalId; Role = $Role; Scope = $Scope })
    Add-DcrFromSchemaWrite -State $State -Write @{ Kind = 'Grant'; PrincipalId = $PrincipalId; Role = $Role; Scope = $Scope }
}

Export-ModuleMember -Function Get-DcrFromSchemaStandIn, Invoke-DcrFromSchemaArm, Invoke-DcrFromSchemaValidate, Invoke-DcrFromSchemaDeploy, Get-DcrFromSchemaDeploymentOperation, Resolve-DcrFromSchemaApp, Get-DcrFromSchemaAssignment, Add-DcrFromSchemaAssignment

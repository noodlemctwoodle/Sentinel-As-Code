#Requires -Version 7.2
#Requires -Modules Az.Accounts, Az.Resources

<#
.SYNOPSIS
    One-time bootstrap of the SharePoint publisher identity the Documenter
    pipeline's SharePoint stage signs in with: the app registration, its
    SharePoint permission, the Azure DevOps service connection and the
    federated credential that ties the two together.

.DESCRIPTION
    The SharePoint stage of Pipelines/Sentinel-Documenter.yml publishes the
    iSOC Blueprint site through an identity that can write to one
    SharePoint site and nothing else in Azure. Setting that identity up by
    hand takes six steps across Entra ID, Azure and Azure DevOps; this
    script does them in order, checks before each change and is safe to
    re-run:

      1. Finds or creates the publisher app registration (no secret, no
         certificate) and its service principal.
      2. Adds the SharePoint Online application permission Sites.Selected
         and grants admin consent for it. This is SharePoint's own
         permission, not Microsoft Graph's Sites.Selected: the publisher
         calls SharePoint's APIs.
      3. Grants the publisher Reader on one (empty) resource group, so the
         AzureCLI task in the pipeline can select a subscription after it
         signs in. An identity that can see no subscription fails there.
      4. Creates the Azure Resource Manager service connection in the ADO
         project with workload identity federation (manual mode), scoped
         to that subscription, and reads back the issuer and subject ADO
         assigned to it.
      5. Adds a federated credential with that issuer and subject to the
         publisher app, audience api://AzureADTokenExchange.
      6. Optionally authorises the Documenter pipeline to use the
         connection and writes sharePointSiteUrl into the deployment
         variable group, so the first run needs no clicks.

    What it does not do: create or prepare the SharePoint site. Run
    Tools/Documenter/SharePoint/Initialize-SentinelDocsSite.ps1 for that
    (it grants this app FullControl on the one site). The script prints
    the exact command with the app id filled in.

    Run it as a user who can create app registrations and grant admin
    consent in Entra ID, assign roles on the resource group, and create
    service connections in the ADO project. Sign in first with
    Connect-AzAccount; Microsoft Graph sign-in is prompted when needed.

.PARAMETER AdoOrganizationUrl
    The Azure DevOps organisation, for example
    https://dev.azure.com/contoso.

.PARAMETER AdoProject
    The project that holds the Documenter pipeline.

.PARAMETER SubscriptionId
    The subscription the service connection is scoped to. The publisher
    needs no role beyond Reader on -ReaderResourceGroup in it.

.PARAMETER ReaderResourceGroup
    An existing, preferably empty, resource group in that subscription.
    The publisher is granted Reader on it and nothing else.

.PARAMETER ServiceConnectionName
    Name of the service connection. Defaults to sc-sentinel-sharepoint,
    which is what the pipeline's sharePointServiceConnection variable
    expects.

.PARAMETER PublisherAppName
    Display name of the publisher app registration. Created when no app
    with this name exists. Ignored when -PublisherAppId is given.

.PARAMETER PublisherAppId
    Client (application) id of an existing publisher app registration to
    use instead of creating one.

.PARAMETER SharePointSiteUrl
    When given, written to the sharePointSiteUrl variable of
    -VariableGroupName.

.PARAMETER VariableGroupName
    The variable group the pipeline reads. Defaults to sentinel-deployment.

.PARAMETER AuthorizePipeline
    Name of a pipeline to authorise for the connection, so its first run
    does not stop at the resource authorisation checkpoint. Defaults to
    Sentinel-Documenter. Pass an empty string to skip.

.PARAMETER AdoPersonalAccessToken
    A personal access token for the organisation (Service Connections
    read, query and manage; Variable Groups read and manage; Build read
    and execute). When omitted the script uses the Azure DevOps token of
    the signed-in Azure account, which works when that account is a
    member of the organisation.

.EXAMPLE
    ./Deploy/setup/Setup-SharePointPublisher.ps1 `
        -AdoOrganizationUrl 'https://dev.azure.com/contoso' `
        -AdoProject 'sentinel-as-code' `
        -SubscriptionId '00000000-0000-0000-0000-000000000000' `
        -ReaderResourceGroup 'rg-sentinel-publisher' `
        -SharePointSiteUrl 'https://contoso.sharepoint.com/sites/isoc-blueprint' `
        -WhatIf

    Prints every change it would make without touching anything.

.EXAMPLE
    ./Deploy/setup/Setup-SharePointPublisher.ps1 `
        -AdoOrganizationUrl 'https://dev.azure.com/contoso' `
        -AdoProject 'sentinel-as-code' `
        -SubscriptionId '00000000-0000-0000-0000-000000000000' `
        -ReaderResourceGroup 'rg-sentinel-publisher'

    Creates everything and prints the Initialize-SentinelDocsSite.ps1
    command to run next.

.NOTES
    File:           Deploy/setup/Setup-SharePointPublisher.ps1
    Repository:     Sentinel-As-Code
    Author:         noodlemctwoodle
    Website:        https://sentinel.blog
    Created:        2026-10-12
    Version:        0.1.1
    Last Updated:   2026-10-12
    Permissions:    Entra ID: create applications and grant admin consent
                    (Application Administrator plus Privileged Role
                    Administrator, or Global Administrator). Azure: User
                    Access Administrator or Owner on the resource group.
                    ADO: project administrator, or Service Connections
                    "Creator" plus variable group and pipeline rights.
    Requires:       PowerShell 7.2+, Az.Accounts, Az.Resources,
                    Microsoft.Graph.Applications (auto-installed if
                    missing, pulling in Microsoft.Graph.Authentication).
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^https://')]
    [string]$AdoOrganizationUrl,

    [Parameter(Mandatory = $true)]
    [string]$AdoProject,

    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $true)]
    [string]$ReaderResourceGroup,

    [Parameter(Mandatory = $false)]
    [string]$ServiceConnectionName = 'sc-sentinel-sharepoint',

    [Parameter(Mandatory = $false)]
    [string]$PublisherAppName = 'Sentinel Documenter SharePoint publisher',

    [Parameter(Mandatory = $false)]
    [string]$PublisherAppId,

    [Parameter(Mandatory = $false)]
    [string]$SharePointSiteUrl,

    [Parameter(Mandatory = $false)]
    [string]$VariableGroupName = 'sentinel-deployment',

    [Parameter(Mandatory = $false)]
    [AllowEmptyString()]
    [string]$AuthorizePipeline = 'Sentinel-Documenter',

    [Parameter(Mandatory = $false)]
    [securestring]$AdoPersonalAccessToken
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# SharePoint Online's first-party application and its Sites.Selected
# application role. These ids are the same in every tenant.
$sharePointResourceAppId = '00000003-0000-0ff1-ce00-000000000000'
$sitesSelectedRoleId     = '20d37865-089c-4dee-8c41-6967602d4ac8'
$adoResourceId           = '499b84ac-1321-427f-aa17-267ca6975798'
$adoApi                  = 'api-version=7.1-preview.4'

function Write-Step { param([string]$Text) Write-Host ""; Write-Host $Text -ForegroundColor Yellow }
function Write-Ok   { param([string]$Text) Write-Host "  $Text" -ForegroundColor Green }
function Write-Skip { param([string]$Text) Write-Host "  $Text" -ForegroundColor DarkGray }

function Get-AdoHeader {
    if ($AdoPersonalAccessToken) {
        $plain = [System.Net.NetworkCredential]::new('', $AdoPersonalAccessToken).Password
        return @{ Authorization = 'Basic ' + [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(":$plain")) }
    }
    $token = (Get-AzAccessToken -ResourceUrl $adoResourceId -ErrorAction Stop).Token
    if ($token -is [securestring]) { $token = [System.Net.NetworkCredential]::new('', $token).Password }
    return @{ Authorization = "Bearer $token" }
}

function Invoke-Ado {
    param(
        [Parameter(Mandatory = $true)] [ValidateSet('GET', 'POST', 'PUT', 'PATCH')] [string]$Method,
        [Parameter(Mandatory = $true)] [string]$Uri,
        [Parameter(Mandatory = $false)] $Body
    )
    $call = @{ Method = $Method; Uri = $Uri; Headers = (Get-AdoHeader); ErrorAction = 'Stop' }
    if ($null -ne $Body) { $call.ContentType = 'application/json'; $call.Body = ($Body | ConvertTo-Json -Depth 12) }
    try { return Invoke-RestMethod @call }
    catch {
        $detail = $_.ErrorDetails.Message
        if ($detail) { throw "Azure DevOps $Method $Uri failed: $detail" }
        throw
    }
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Sentinel-As-Code: SharePoint publisher bootstrap" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# ---- 0. Sign-ins -----------------------------------------------------------
Write-Step "Verifying Azure sign-in..."
$context = Get-AzContext -WarningAction SilentlyContinue
if (-not $context) { throw 'Not authenticated. Run Connect-AzAccount first.' }
Set-AzContext -SubscriptionId $SubscriptionId -WarningAction SilentlyContinue -WhatIf:$false | Out-Null
$context = Get-AzContext -WarningAction SilentlyContinue
$tenantId = $context.Tenant.Id
$subscriptionName = $context.Subscription.Name
Write-Ok "Account:      $($context.Account.Id)"
Write-Ok "Tenant:       $tenantId"
Write-Ok "Subscription: $subscriptionName ($SubscriptionId)"

Write-Step "Connecting to Microsoft Graph (applications)..."
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Applications)) {
    Write-Host "  Installing Microsoft.Graph.Applications..." -ForegroundColor DarkGray
    Install-Module -Name Microsoft.Graph.Applications -Force -Scope CurrentUser -AllowClobber
}
Import-Module Microsoft.Graph.Applications -ErrorAction Stop
$mg = Get-MgContext
$neededScopes = @('Application.ReadWrite.All', 'AppRoleAssignment.ReadWrite.All')
if (-not $mg -or @($neededScopes | Where-Object { $mg.Scopes -notcontains $_ }).Count -gt 0) {
    Connect-MgGraph -Scopes ($neededScopes -join ',') -TenantId $tenantId -NoWelcome
    $mg = Get-MgContext
}
Write-Ok "Graph account: $($mg.Account)"

# ---- 1. Publisher app registration ------------------------------------------
Write-Step "Publisher app registration..."
$app = $null
if ($PublisherAppId) {
    $app = Get-MgApplication -Filter "appId eq '$PublisherAppId'" -ErrorAction Stop | Select-Object -First 1
    if (-not $app) { throw "No app registration with client id '$PublisherAppId'." }
} else {
    $safeName = $PublisherAppName.Replace("'", "''")
    $app = Get-MgApplication -Filter "displayName eq '$safeName'" -ErrorAction Stop | Select-Object -First 1
}
if ($app) {
    Write-Ok "Using '$($app.DisplayName)' ($($app.AppId))"
} elseif ($PSCmdlet.ShouldProcess($PublisherAppName, 'Create app registration')) {
    $app = New-MgApplication -DisplayName $PublisherAppName -SignInAudience 'AzureADMyOrg' -Notes 'Sentinel-As-Code Documenter: publishes the iSOC Blueprint SharePoint site. No secret; federated credential per pipeline.' -ErrorAction Stop
    Write-Ok "Created '$($app.DisplayName)' ($($app.AppId))"
} else {
    Write-Skip "Would create app registration '$PublisherAppName'"
}
$appId = if ($app) { $app.AppId } else { '<new-app-id>' }

$sp = $null
if ($app) {
    $sp = Get-MgServicePrincipal -Filter "appId eq '$($app.AppId)'" -ErrorAction Stop | Select-Object -First 1
    if ($sp) {
        Write-Ok "Service principal present ($($sp.Id))"
    } elseif ($PSCmdlet.ShouldProcess($app.DisplayName, 'Create service principal')) {
        $sp = New-MgServicePrincipal -AppId $app.AppId -ErrorAction Stop
        Write-Ok "Created service principal ($($sp.Id))"
    } else {
        Write-Skip 'Would create the service principal'
    }
}

# ---- 2. SharePoint Sites.Selected with admin consent ------------------------
Write-Step "SharePoint application permission Sites.Selected..."
if ($app) {
    $spoAccess = @($app.RequiredResourceAccess | Where-Object { $_.ResourceAppId -eq $sharePointResourceAppId })
    $hasRole = @($spoAccess | ForEach-Object { $_.ResourceAccess } | Where-Object { $_.Id -eq $sitesSelectedRoleId -and $_.Type -eq 'Role' }).Count -gt 0
    if ($hasRole) {
        Write-Ok 'Declared on the app'
    } elseif ($PSCmdlet.ShouldProcess($app.DisplayName, 'Add SharePoint Sites.Selected (application) to required permissions')) {
        $required = @($app.RequiredResourceAccess | Where-Object { $_.ResourceAppId -ne $sharePointResourceAppId })
        $required += @{ ResourceAppId = $sharePointResourceAppId; ResourceAccess = @(@{ Id = $sitesSelectedRoleId; Type = 'Role' }) }
        Update-MgApplication -ApplicationId $app.Id -RequiredResourceAccess $required -ErrorAction Stop
        Write-Ok 'Declared on the app'
    } else {
        Write-Skip 'Would declare Sites.Selected on the app'
    }
}
if ($sp) {
    $spoSp = Get-MgServicePrincipal -Filter "appId eq '$sharePointResourceAppId'" -ErrorAction Stop | Select-Object -First 1
    if (-not $spoSp) { throw 'SharePoint Online service principal not found in this tenant. Is SharePoint licensed here?' }
    $grant = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $sp.Id -ErrorAction SilentlyContinue |
        Where-Object { $_.ResourceId -eq $spoSp.Id -and $_.AppRoleId -eq $sitesSelectedRoleId }
    if ($grant) {
        Write-Ok 'Admin consent granted'
    } elseif ($PSCmdlet.ShouldProcess($app.DisplayName, 'Grant admin consent for SharePoint Sites.Selected')) {
        New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $sp.Id -PrincipalId $sp.Id -ResourceId $spoSp.Id -AppRoleId $sitesSelectedRoleId -ErrorAction Stop | Out-Null
        Write-Ok 'Admin consent granted'
    } else {
        Write-Skip 'Would grant admin consent'
    }
}

# ---- 3. Reader on one resource group ----------------------------------------
Write-Step "Reader on resource group '$ReaderResourceGroup'..."
$rg = Get-AzResourceGroup -Name $ReaderResourceGroup -ErrorAction SilentlyContinue
if (-not $rg) { throw "Resource group '$ReaderResourceGroup' does not exist in subscription $SubscriptionId. Create an empty one first; the publisher needs a subscription it can see." }
if ($sp) {
    $existing = Get-AzRoleAssignment -ObjectId $sp.Id -RoleDefinitionName 'Reader' -Scope $rg.ResourceId -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Ok 'Already assigned'
    } elseif ($PSCmdlet.ShouldProcess($rg.ResourceId, "Assign Reader to $($app.DisplayName)")) {
        # ObjectType skips the directory lookup, which fails while a new service principal replicates.
        New-AzRoleAssignment -ObjectId $sp.Id -ObjectType 'ServicePrincipal' -RoleDefinitionName 'Reader' -Scope $rg.ResourceId -ErrorAction Stop | Out-Null
        Write-Ok 'Assigned'
    } else {
        Write-Skip 'Would assign Reader'
    }
} else {
    Write-Skip 'Would assign Reader once the service principal exists'
}

# ---- 4. ADO service connection (workload identity federation, manual) -------
Write-Step "Service connection '$ServiceConnectionName' in $AdoOrganizationUrl/$AdoProject..."
$org = $AdoOrganizationUrl.TrimEnd('/')
$projectUri = "$org/$([uri]::EscapeDataString($AdoProject))"
$project = Invoke-Ado -Method GET -Uri "$org/_apis/projects/$([uri]::EscapeDataString($AdoProject))?api-version=7.1"
$endpoints = Invoke-Ado -Method GET -Uri "$projectUri/_apis/serviceendpoint/endpoints?endpointNames=$([uri]::EscapeDataString($ServiceConnectionName))&$adoApi"
$endpoint = @($endpoints.value | Where-Object { $_.name -eq $ServiceConnectionName }) | Select-Object -First 1
if ($endpoint) {
    Write-Ok "Exists (id $($endpoint.id))"
} elseif ($PSCmdlet.ShouldProcess("$AdoProject/$ServiceConnectionName", 'Create Azure Resource Manager service connection (workload identity federation)')) {
    if (-not $app) { throw 'The app registration must exist before the service connection can be created. Re-run without -WhatIf.' }
    $body = [ordered]@{
        name          = $ServiceConnectionName
        type          = 'azurerm'
        url           = 'https://management.azure.com/'
        description   = 'Sentinel Documenter SharePoint publisher. Writes one SharePoint site, holds no Azure role beyond Reader on one resource group.'
        authorization = @{ scheme = 'WorkloadIdentityFederation'; parameters = @{ tenantid = $tenantId; serviceprincipalid = $app.AppId } }
        data          = @{ environment = 'AzureCloud'; scopeLevel = 'Subscription'; subscriptionId = $SubscriptionId; subscriptionName = $subscriptionName; creationMode = 'Manual' }
        isShared      = $false
        isReady       = $true
        serviceEndpointProjectReferences = @(@{ projectReference = @{ id = $project.id; name = $project.name }; name = $ServiceConnectionName })
    }
    $endpoint = Invoke-Ado -Method POST -Uri "$projectUri/_apis/serviceendpoint/endpoints?$adoApi" -Body $body
    Write-Ok "Created (id $($endpoint.id))"
} else {
    Write-Skip 'Would create the service connection'
}

$issuer = $null; $subject = $null
if ($endpoint) {
    $endpoint = Invoke-Ado -Method GET -Uri "$projectUri/_apis/serviceendpoint/endpoints/$($endpoint.id)?$adoApi"
    $params = $endpoint.authorization.parameters
    if ($params.PSObject.Properties['workloadIdentityFederationIssuer'])  { $issuer  = $params.workloadIdentityFederationIssuer }
    if ($params.PSObject.Properties['workloadIdentityFederationSubject']) { $subject = $params.workloadIdentityFederationSubject }
}
if (-not $issuer) {
    $conn = Invoke-Ado -Method GET -Uri "$org/_apis/connectionData?api-version=7.1-preview.1"
    $issuer = "https://vstoken.dev.azure.com/$($conn.instanceId)"
}
if (-not $subject) {
    $orgName = ($org -split '/')[-1]
    $subject = "sc://$orgName/$AdoProject/$ServiceConnectionName"
}
Write-Ok "Issuer:  $issuer"
Write-Ok "Subject: $subject"

# ---- 5. Federated credential on the app -------------------------------------
Write-Step "Federated credential on the publisher app..."
if ($app) {
    $creds = @(Get-MgApplicationFederatedIdentityCredential -ApplicationId $app.Id -ErrorAction SilentlyContinue)
    $cred = $creds | Where-Object { $_.Issuer -eq $issuer -and $_.Subject -eq $subject } | Select-Object -First 1
    if ($cred) {
        Write-Ok "Present ('$($cred.Name)')"
    } elseif ($PSCmdlet.ShouldProcess($app.DisplayName, "Add federated credential for $subject")) {
        $credName = ('ado-' + $AdoProject + '-' + $ServiceConnectionName) -replace '[^A-Za-z0-9_-]', '-'
        if ($credName.Length -gt 120) { $credName = $credName.Substring(0, 120) }
        New-MgApplicationFederatedIdentityCredential -ApplicationId $app.Id -Name $credName -Issuer $issuer -Subject $subject -Audiences @('api://AzureADTokenExchange') -Description "Azure DevOps service connection $ServiceConnectionName" -ErrorAction Stop | Out-Null
        Write-Ok "Added ('$credName')"
    } else {
        Write-Skip 'Would add the federated credential'
    }
}

# ---- 6. Pipeline authorisation and the site URL variable --------------------
if ($AuthorizePipeline -and $endpoint) {
    Write-Step "Authorising pipeline '$AuthorizePipeline' to use the connection..."
    $pipelines = Invoke-Ado -Method GET -Uri "$projectUri/_apis/pipelines?api-version=7.1"
    $pipeline = @($pipelines.value | Where-Object { $_.name -eq $AuthorizePipeline }) | Select-Object -First 1
    if (-not $pipeline) {
        Write-Skip "Pipeline '$AuthorizePipeline' not found; the first run will ask for permission instead"
    } else {
        $perm = Invoke-Ado -Method GET -Uri "$projectUri/_apis/pipelines/pipelinepermissions/endpoint/$($endpoint.id)?api-version=7.1-preview.1"
        $already = @($perm.pipelines | Where-Object { $_.id -eq $pipeline.id -and $_.authorized }).Count -gt 0
        if ($already) {
            Write-Ok 'Already authorised'
        } elseif ($PSCmdlet.ShouldProcess("$AuthorizePipeline (pipeline $($pipeline.id))", "Authorise for $ServiceConnectionName")) {
            Invoke-Ado -Method PATCH -Uri "$projectUri/_apis/pipelines/pipelinepermissions/endpoint/$($endpoint.id)?api-version=7.1-preview.1" -Body @{ pipelines = @(@{ id = $pipeline.id; authorized = $true }) } | Out-Null
            Write-Ok 'Authorised'
        } else {
            Write-Skip 'Would authorise'
        }
    }
}

if ($SharePointSiteUrl) {
    Write-Step "Variable sharePointSiteUrl in group '$VariableGroupName'..."
    $groups = Invoke-Ado -Method GET -Uri "$projectUri/_apis/distributedtask/variablegroups?groupName=$([uri]::EscapeDataString($VariableGroupName))&api-version=7.1-preview.2"
    $group = @($groups.value | Where-Object { $_.name -eq $VariableGroupName }) | Select-Object -First 1
    if (-not $group) {
        Write-Skip "Variable group '$VariableGroupName' not found; set sharePointSiteUrl by hand"
    } else {
        $current = if ($group.variables.PSObject.Properties['sharePointSiteUrl']) { $group.variables.sharePointSiteUrl.value } else { $null }
        if ($current -eq $SharePointSiteUrl) {
            Write-Ok 'Already set'
        } elseif ($PSCmdlet.ShouldProcess("$VariableGroupName/sharePointSiteUrl", "Set to $SharePointSiteUrl")) {
            # ADO omits isSecret on plain variables and description on groups without one.
            $vars = [ordered]@{}
            foreach ($p in $group.variables.PSObject.Properties) {
                $isSecret = $p.Value.PSObject.Properties['isSecret'] -and [bool]$p.Value.isSecret
                $value = if ($p.Value.PSObject.Properties['value']) { $p.Value.value } else { $null }
                $vars[$p.Name] = @{ value = $value; isSecret = $isSecret }
            }
            $vars['sharePointSiteUrl'] = @{ value = $SharePointSiteUrl; isSecret = $false }
            $groupDescription = if ($group.PSObject.Properties['description']) { $group.description } else { '' }
            $update = [ordered]@{
                id = $group.id; name = $group.name; type = $group.type; description = $groupDescription
                variables = $vars
                variableGroupProjectReferences = @(@{ projectReference = @{ id = $project.id; name = $project.name }; name = $group.name; description = $groupDescription })
            }
            Invoke-Ado -Method PUT -Uri "$org/_apis/distributedtask/variablegroups/$($group.id)?api-version=7.1-preview.2" -Body $update | Out-Null
            Write-Ok 'Set'
        } else {
            Write-Skip 'Would set'
        }
    }
}

# ---- Summary ---------------------------------------------------------------
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Done. Next steps" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  1. Verify the connection in ADO (Project settings, Service connections, $ServiceConnectionName, Verify)."
Write-Host "  2. Prepare the site once, as a SharePoint administrator (adds the site app catalog and grants this app FullControl on that site only):"
Write-Host ""
Write-Host "     ./Tools/Documenter/SharePoint/Initialize-SentinelDocsSite.ps1 ``" -ForegroundColor White
Write-Host "         -SiteUrl '$(if ($SharePointSiteUrl) { $SharePointSiteUrl } else { '<site url>' })' -Owner '<owner upn>' ``" -ForegroundColor White
Write-Host "         -PublisherAppId '$appId' -ClientId '<your PnP sign-in app id>' -Tenant '<tenant>.onmicrosoft.com' -WhatIf" -ForegroundColor White
Write-Host ""
Write-Host "  3. Queue Sentinel-Documenter with 'SharePoint site' and its what-if ticked, read the plan, then run it for real."
Write-Host ""

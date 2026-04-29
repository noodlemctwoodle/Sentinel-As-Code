#
# Sentinel-As-Code/Modules/Sentinel.Common/Sentinel.Common.psm1
#
# Created by noodlemctwoodle on 29/04/2026.
#

<#
.SYNOPSIS
    Shared helpers used across the Sentinel-As-Code deployer scripts and the
    drift-detection script. Removes the byte-identical Write-PipelineMessage
    duplication and consolidates the divergent Invoke-SentinelApi /
    Connect-AzureEnvironment copies onto a single source of truth per
    Wave 4 plan Item 1.

.DESCRIPTION
    Three exported functions:

    - Write-PipelineMessage — ADO/GitHub/local-friendly logging abstraction.
      Same output shape regardless of platform; callers do not need to care
      where the script runs.

    - Invoke-SentinelApi — REST-API wrapper with retry-on-transient-failure
      semantics (HTTP 429 / 500 / 502 / 503 / 504), defensive response-body
      recovery via StreamReader for non-JSON error responses, and
      typed-exception throw on terminal failure.

    - Connect-AzureEnvironment — Az PowerShell context bootstrap with
      government-cloud branching, optional separate playbook resource group,
      access-token acquisition (with profile-client fallback for environments
      where Get-AzAccessToken is restricted), and workspace ID retrieval.
      Returns a hashtable of derived state the caller assigns to its own
      script scope (callers historically relied on the function mutating
      script scope in-place; that pattern doesn't survive module extraction
      because $script: in a module refers to the module's scope, not the
      caller's).

.NOTES
    Author:         noodlemctwoodle
    Version:        1.0.0
    Last Updated:   2026-04-29
    Repository:     Sentinel-As-Code
    Requires:       PowerShell 7.2+, Az.Accounts
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ===========================================================================
# Write-PipelineMessage
# ===========================================================================
# Byte-identical across all four pre-extraction copies (Deploy-CustomContent,
# Deploy-SentinelContentHub, Deploy-DefenderDetections, Test-SentinelRuleDrift).
# Direct copy.
function Write-PipelineMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Message
        ,
        [Parameter(Mandatory = $false)]
        [ValidateSet("Info", "Warning", "Error", "Section", "Success", "Debug")]
        [string]$Level = "Info"
    )

    $isAdo = $null -ne $env:BUILD_BUILDID

    switch ($Level) {
        "Info"    {
            Write-Host $Message
        }
        "Warning" {
            if ($isAdo) {
                Write-Host "##[warning]$Message"
            }
            else {
                Write-Warning $Message
            }
        }
        "Error"   {
            if ($isAdo) {
                Write-Host "##[error]$Message"
            }
            else {
                Write-Error $Message -ErrorAction Continue
            }
        }
        "Section" {
            if ($isAdo) {
                Write-Host "##[section]$Message"
            }
            else {
                Write-Host "`n$Message" -ForegroundColor Cyan
            }
        }
        "Success" {
            if ($isAdo) {
                Write-Host $Message
            }
            else {
                Write-Host $Message -ForegroundColor Green
            }
        }
        "Debug"   {
            Write-Verbose $Message
        }
    }
}

# ===========================================================================
# Invoke-SentinelApi
# ===========================================================================
# Source of truth: Deploy-SentinelContentHub.ps1 (lines 284-358 pre-extraction).
# This implementation has the most defensive error-recovery pattern:
# StreamReader-based response-body extraction for non-JSON 4xx/5xx responses,
# fallback to ErrorDetails.Message, retry on documented-transient HTTP codes.
function Invoke-SentinelApi {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri
        ,
        [Parameter(Mandatory = $true)]
        [string]$Method
        ,
        [Parameter(Mandatory = $true)]
        [hashtable]$Headers
        ,
        [Parameter(Mandatory = $false)]
        [string]$Body
        ,
        [Parameter(Mandatory = $false)]
        [int]$MaxRetries = 3
        ,
        [Parameter(Mandatory = $false)]
        [int]$RetryDelaySeconds = 5
    )

    $attempt = 0

    while ($attempt -lt $MaxRetries) {
        $attempt++

        try {
            $params = @{
                Uri         = $Uri
                Method      = $Method
                Headers     = $Headers
                ContentType = 'application/json'
            }

            if ($Body) {
                $params.Body = $Body
            }

            $webResponse = Invoke-WebRequest @params -UseBasicParsing -ErrorAction Stop
            return ($webResponse.Content | ConvertFrom-Json)
        }
        catch {
            $statusCode = $null
            $responseBody = $null

            # Strict-mode-safe property access: $_.Exception.Response only
            # exists on WebException-flavoured errors. Vanilla [Exception]
            # instances hit a property-not-found under Set-StrictMode without
            # this guard. Use the PSObject reflection API which returns null
            # on absence rather than throwing.
            $responseProperty = $_.Exception.PSObject.Properties['Response']
            if ($responseProperty -and $responseProperty.Value) {
                $exResponse = $responseProperty.Value
                $statusCode = [int]$exResponse.StatusCode
                try {
                    $stream = $exResponse.GetResponseStream()
                    $reader = [System.IO.StreamReader]::new($stream)
                    $responseBody = $reader.ReadToEnd()
                    $reader.Dispose()
                }
                catch { }
            }

            $errorDetailsProp = $_.PSObject.Properties['ErrorDetails']
            if (-not $responseBody -and $errorDetailsProp -and $errorDetailsProp.Value -and $errorDetailsProp.Value.Message) {
                $responseBody = $errorDetailsProp.Value.Message
            }

            # Retry on throttling (429) or transient server errors (500, 502, 503, 504)
            $retryableCodes = @(429, 500, 502, 503, 504)
            if ($statusCode -and $retryableCodes -contains $statusCode -and $attempt -lt $MaxRetries) {
                $delay = $RetryDelaySeconds * $attempt
                Write-PipelineMessage "API call returned $statusCode. Retrying in ${delay}s (attempt $attempt of $MaxRetries)..." -Level Warning
                Start-Sleep -Seconds $delay
                continue
            }

            $errorDetail = if ($responseBody) { "HTTP $statusCode - $responseBody" } else { $_.Exception.Message }
            throw "API call failed: $errorDetail"
        }
    }
}

# ===========================================================================
# Connect-AzureEnvironment
# ===========================================================================
# Source of truth: Deploy-CustomContent.ps1 (lines 654-757 pre-extraction).
# That version had the most-complete behaviour: playbook-RG validation +
# workspace-ID retrieval + profile-client token fallback.
#
# Refactor for the module: the original mutated $script: scope of the caller
# directly. That doesn't work across a module boundary (the module's $script:
# is the module's scope, not the caller's). The function now takes explicit
# parameters and returns a hashtable of derived state. Callers assign to
# their own script-scope vars:
#
#     $ctx = Connect-AzureEnvironment -ResourceGroup $ResourceGroup `
#                                     -Workspace $Workspace `
#                                     -Region $Region `
#                                     -SubscriptionId $script:SubscriptionId `
#                                     -IsGov:$IsGov `
#                                     -PlaybookResourceGroup $PlaybookResourceGroup
#     $script:SubscriptionId      = $ctx.SubscriptionId
#     $script:ServerUrl           = $ctx.ServerUrl
#     $script:BaseUri             = $ctx.BaseUri
#     $script:WorkspaceResourceId = $ctx.WorkspaceResourceId
#     $script:WorkspaceId         = $ctx.WorkspaceId
#     $script:PlaybookRG          = $ctx.PlaybookRG
#     $script:AuthHeader          = $ctx.AuthHeader
function Connect-AzureEnvironment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroup
        ,
        [Parameter(Mandatory = $true)]
        [string]$Workspace
        ,
        [Parameter(Mandatory = $true)]
        [string]$Region
        ,
        [Parameter(Mandatory = $false)]
        [string]$SubscriptionId
        ,
        [Parameter(Mandatory = $false)]
        [switch]$IsGov
        ,
        [Parameter(Mandatory = $false)]
        [string]$PlaybookResourceGroup
        ,
        [Parameter(Mandatory = $false)]
        [string]$WorkspaceApiVersion = "2022-10-01"
    )

    Write-PipelineMessage "Establishing Azure authentication..." -Level Section

    # Suppress Az module version upgrade warnings
    Update-AzConfig -DisplayBreakingChangeWarning $false -ErrorAction SilentlyContinue -WarningAction SilentlyContinue | Out-Null

    $context = Get-AzContext -WarningAction SilentlyContinue

    if (-not $context) {
        Write-PipelineMessage "No Azure context found. Attempting login..." -Level Info
        if ($IsGov) {
            Connect-AzAccount -Environment AzureUSGovernment -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null
        }
        else {
            Connect-AzAccount -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null
        }
        $context = Get-AzContext -WarningAction SilentlyContinue
    }

    if (-not $context) {
        throw "Failed to establish Azure context. Ensure you are authenticated."
    }

    # Resolve subscription: prefer explicit parameter, else current context.
    if ($SubscriptionId) {
        Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null
        $context = Get-AzContext -WarningAction SilentlyContinue
    }
    else {
        $SubscriptionId = $context.Subscription.Id
    }

    Write-PipelineMessage "Authenticated to subscription: $($context.Subscription.Id) ($($context.Subscription.Name))" -Level Success

    $serverUrl = if ($IsGov) {
        "https://management.usgovcloudapi.net"
    }
    else {
        "https://management.azure.com"
    }

    $baseUri = "$serverUrl/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$Workspace"
    $workspaceResourceId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$Workspace"
    $playbookRG = if ($PlaybookResourceGroup) { $PlaybookResourceGroup } else { $ResourceGroup }

    # Acquire access token. Try Get-AzAccessToken first; fall back to the
    # profile client for environments where the cmdlet is restricted.
    try {
        $tokenResponse = Get-AzAccessToken -ResourceUrl $serverUrl -ErrorAction Stop -WarningAction SilentlyContinue

        if ($tokenResponse.Token -is [System.Security.SecureString]) {
            $accessToken = $tokenResponse.Token | ConvertFrom-SecureString -AsPlainText
        }
        elseif ($tokenResponse.Token -is [string]) {
            $accessToken = $tokenResponse.Token
        }
        else {
            throw "Unexpected token type: $($tokenResponse.Token.GetType().FullName)"
        }
    }
    catch {
        Write-PipelineMessage "Get-AzAccessToken failed ($($_.Exception.Message)). Falling back to context profile token." -Level Warning
        $instanceProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile
        $profileClient = New-Object -TypeName Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient -ArgumentList ($instanceProfile)
        $tokenObj = $profileClient.AcquireAccessToken($context.Subscription.TenantId)
        $accessToken = $tokenObj.AccessToken
    }

    if (-not $accessToken) {
        throw "Failed to acquire an access token. Check Service Principal permissions."
    }

    $authHeader = @{
        'Content-Type'  = 'application/json'
        'Authorization' = "Bearer $accessToken"
    }

    Write-PipelineMessage "Target workspace: $Workspace (Resource Group: $ResourceGroup, Region: $Region)" -Level Info
    if ($playbookRG -ne $ResourceGroup) {
        $playbookRgCheck = Get-AzResourceGroup -Name $playbookRG -ErrorAction SilentlyContinue
        if (-not $playbookRgCheck) {
            throw "Playbook resource group '$playbookRG' does not exist. Create it via Bicep (set the playbookRgName parameter in main.bicep) or manually in the Azure portal before running the pipeline."
        }
        Write-PipelineMessage "Playbooks will deploy to resource group: $playbookRG" -Level Info
    }
    if ($IsGov) {
        Write-PipelineMessage "Azure Government cloud mode enabled." -Level Info
    }

    # Retrieve the workspace ID (GUID) for playbook parameter injection.
    # Non-fatal — proceed with $null on failure.
    $workspaceId = $null
    try {
        $wsUri = "$serverUrl/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.OperationalInsights/workspaces/${Workspace}?api-version=$WorkspaceApiVersion"
        $wsResponse = Invoke-SentinelApi -Uri $wsUri -Method Get -Headers $authHeader
        $workspaceId = $wsResponse.properties.customerId
        Write-PipelineMessage "Workspace ID: $workspaceId" -Level Info
    }
    catch {
        Write-PipelineMessage "Could not retrieve workspace ID: $($_.Exception.Message)" -Level Warning
    }

    return @{
        SubscriptionId      = $SubscriptionId
        ServerUrl           = $serverUrl
        BaseUri             = $baseUri
        WorkspaceResourceId = $workspaceResourceId
        WorkspaceId         = $workspaceId
        PlaybookRG          = $playbookRG
        AuthHeader          = $authHeader
    }
}

Export-ModuleMember -Function Write-PipelineMessage, Invoke-SentinelApi, Connect-AzureEnvironment

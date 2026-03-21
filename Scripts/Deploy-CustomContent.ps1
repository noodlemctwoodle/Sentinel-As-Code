<#
.SYNOPSIS
    Deploys custom Microsoft Sentinel content from the repository to a workspace.

.DESCRIPTION
    This script automates the deployment of custom Sentinel content stored in the
    repository: parsers (KQL functions), analytics rules (detections), watchlists,
    playbooks, workbooks, hunting queries, and automation rules.

    It is designed to run in Azure DevOps (ADO) pipelines using a Service Principal
    or Managed Identity for authentication. The script uses the latest GA API version
    (2025-07-01-preview) for Sentinel operations, enabling sub-technique
    mappings, sentinelEntitiesMappings, and native NRT rule support.

    Key capabilities:
    - Deploy KQL parsers/functions from YAML files (workspace functions)
    - Deploy custom analytics rules from YAML files (Scheduled and NRT)
    - Deploy watchlists from JSON metadata + CSV data files
    - Deploy playbooks from ARM JSON templates
    - Deploy workbooks from gallery template JSON files
    - Deploy hunting queries from YAML files (saved searches)
    - Deploy automation rules from JSON files
    - Deploy summary rules from JSON files (Log Analytics summarylogs)
    - Granular control via switches for each content type
    - WhatIf mode for dry runs

.PARAMETER SubscriptionId
    The Azure Subscription ID containing the Sentinel workspace. If not provided,
    the script will attempt to use the current Azure context.

.PARAMETER ResourceGroup
    The name of the Azure Resource Group containing the Sentinel workspace.

.PARAMETER PlaybookResourceGroup
    Optional. The name of the Azure Resource Group where playbooks (Logic Apps)
    should be deployed. If not specified, playbooks deploy to the same resource
    group as the Sentinel workspace.

.PARAMETER Workspace
    The name of the Log Analytics workspace with Microsoft Sentinel enabled.

.PARAMETER Region
    The Azure region (location) where the workspace is deployed (e.g. 'uksouth').

.PARAMETER BasePath
    The root path of the repository containing content folders (AnalyticalRules/,
    Watchlists/, Playbooks/, Workbooks/). Defaults to the parent of the Scripts folder.

.PARAMETER SkipParsers
    When specified, skips deploying KQL parsers/functions.

.PARAMETER SkipDetections
    When specified, skips deploying custom analytics rules.

.PARAMETER SkipWatchlists
    When specified, skips deploying custom watchlists.

.PARAMETER SkipPlaybooks
    When specified, skips deploying custom playbooks.

.PARAMETER SkipWorkbooks
    When specified, skips deploying custom workbooks.

.PARAMETER SkipHuntingQueries
    When specified, skips deploying custom hunting queries.

.PARAMETER SkipAutomationRules
    When specified, skips deploying custom automation rules.

.PARAMETER SkipSummaryRules
    When specified, skips deploying custom summary rules.

.PARAMETER IsGov
    When specified, targets the Azure Government cloud environment.

.PARAMETER WhatIf
    When specified, performs a dry run showing what actions would be taken without
    making changes.

.NOTES
    Author:         noodlemctwoodle
    Version:        1.0.0
    Last Updated:   2026-03-20
    Repository:     Sentinel-As-Code
    API Version:    2025-07-01-preview
    Requires:       Az.Accounts, powershell-yaml

.EXAMPLE
    .\Deploy-CustomContent.ps1 `
        -ResourceGroup "rg-sentinel-prod" `
        -Workspace "law-sentinel-prod" `
        -Region "uksouth"

    Deploys all custom content from the repository.

.EXAMPLE
    .\Deploy-CustomContent.ps1 `
        -ResourceGroup "rg-sentinel-prod" `
        -Workspace "law-sentinel-prod" `
        -Region "uksouth" `
        -SkipPlaybooks `
        -SkipWorkbooks

    Deploys only custom detections and watchlists.

.EXAMPLE
    .\Deploy-CustomContent.ps1 `
        -ResourceGroup "rg-sentinel-prod" `
        -Workspace "law-sentinel-prod" `
        -Region "uksouth" `
        -WhatIf

    Performs a dry run showing what would be deployed.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId
    ,
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroup
    ,
    [Parameter(Mandatory = $false)]
    [string]$PlaybookResourceGroup
    ,
    [Parameter(Mandatory = $true)]
    [string]$Workspace
    ,
    [Parameter(Mandatory = $true)]
    [string]$Region
    ,
    [Parameter(Mandatory = $false)]
    [string]$BasePath
    ,
    [Parameter(Mandatory = $false)]
    [switch]$SkipParsers
    ,
    [Parameter(Mandatory = $false)]
    [switch]$SkipDetections
    ,
    [Parameter(Mandatory = $false)]
    [switch]$SkipWatchlists
    ,
    [Parameter(Mandatory = $false)]
    [switch]$SkipPlaybooks
    ,
    [Parameter(Mandatory = $false)]
    [switch]$SkipWorkbooks
    ,
    [Parameter(Mandatory = $false)]
    [switch]$SkipHuntingQueries
    ,
    [Parameter(Mandatory = $false)]
    [switch]$SkipAutomationRules
    ,
    [Parameter(Mandatory = $false)]
    [switch]$SkipSummaryRules
    ,
    [Parameter(Mandatory = $false)]
    [switch]$IsGov
    ,
    [Parameter(Mandatory = $false)]
    [switch]$SmartDeployment
    ,
    [Parameter(Mandatory = $false)]
    [switch]$WhatIf
)

#Requires -Modules Az.Accounts

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$InformationPreference = "Continue"

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
$script:SentinelApiVersion  = "2025-07-01-preview"
$script:WorkbookApiVersion  = "2022-04-01"
$script:SavedSearchApiVersion = "2025-07-01"
$script:SummaryRuleApiVersion = "2025-07-01"

# ---------------------------------------------------------------------------
# Resolve BasePath
# ---------------------------------------------------------------------------
if (-not $BasePath) {
    $BasePath = Split-Path $PSScriptRoot -Parent
}

# ---------------------------------------------------------------------------
# Smart Deployment: Config loader, git diff change detection, exclusions
# ---------------------------------------------------------------------------
$script:DeploymentConfig = $null
$script:ChangedFiles = $null
$script:SmartDeploymentActive = $false

function Initialize-SmartDeployment {
    [CmdletBinding()]
    param()

    # Load sentinel-deployment.config if present
    $configPath = Join-Path $BasePath "sentinel-deployment.config"
    if (Test-Path $configPath) {
        try {
            $script:DeploymentConfig = Get-Content -Path $configPath -Raw | ConvertFrom-Json
            Write-PipelineMessage "Loaded sentinel-deployment.config" -Level Info

            $excluded = @()
            if ($script:DeploymentConfig.PSObject.Properties.Name -contains 'excludecontentfiles') {
                $excluded = @($script:DeploymentConfig.excludecontentfiles)
            }
            if ($excluded.Count -gt 0) {
                Write-PipelineMessage "  Excluded paths: $($excluded -join ', ')" -Level Info
            }

            $prioritized = @()
            if ($script:DeploymentConfig.PSObject.Properties.Name -contains 'prioritizedcontentfiles') {
                $prioritized = @($script:DeploymentConfig.prioritizedcontentfiles)
            }
            if ($prioritized.Count -gt 0) {
                Write-PipelineMessage "  Prioritized files: $($prioritized -join ', ')" -Level Info
            }
        }
        catch {
            Write-PipelineMessage "Failed to parse sentinel-deployment.config: $($_.Exception.Message)" -Level Warning
        }
    }

    if (-not $SmartDeployment) {
        Write-PipelineMessage "Smart deployment disabled — all content will be deployed." -Level Info
        return
    }

    Write-PipelineMessage "Smart deployment enabled — detecting changed files..." -Level Section

    # Determine changed files via git diff
    try {
        Push-Location $BasePath

        # In ADO pipelines, use the merge base to find all changed files in this push
        # BUILD_SOURCEVERSION is the current commit, SYSTEM_PULLREQUEST_TARGETBRANCH for PRs
        $changedFiles = $null

        if ($env:BUILD_SOURCEBRANCH -and $env:SYSTEM_PULLREQUEST_TARGETBRANCH) {
            # PR trigger — diff against target branch
            $targetBranch = $env:SYSTEM_PULLREQUEST_TARGETBRANCH -replace '^refs/heads/', ''
            git fetch --depth=1 origin $targetBranch 2>$null | Out-Null
            $changedFiles = git diff --name-only "origin/$targetBranch...HEAD" 2>$null
        }
        elseif ($env:BUILD_SOURCEVERSION) {
            # CI trigger — ADO shallow clones with depth=1. Deepen by 1 to get the parent commit.
            git fetch --deepen=1 2>$null | Out-Null
            $changedFiles = git diff --name-only HEAD~1 HEAD 2>$null

            # Fallback: if deepen didn't work, try fetching the full branch
            if ($LASTEXITCODE -ne 0 -or -not $changedFiles) {
                $branch = $env:BUILD_SOURCEBRANCH -replace '^refs/heads/', ''
                git fetch --depth=2 origin $branch 2>$null | Out-Null
                $changedFiles = git diff --name-only HEAD~1 HEAD 2>$null
            }
        }
        else {
            # Local run — diff against HEAD~1
            $changedFiles = git diff --name-only HEAD~1 HEAD 2>$null
        }

        $changedFiles = @($changedFiles | Where-Object { $_ })
        if ($changedFiles.Count -gt 0) {
            $script:ChangedFiles = $changedFiles
            $script:SmartDeploymentActive = $true
            Write-PipelineMessage "  Detected $($script:ChangedFiles.Count) changed file(s):" -Level Info
            foreach ($cf in $script:ChangedFiles) {
                Write-PipelineMessage "    - $cf" -Level Info
            }
        }
        else {
            Write-PipelineMessage "  Could not determine changed files — deploying all content." -Level Warning
        }
    }
    catch {
        Write-PipelineMessage "  Git diff failed: $($_.Exception.Message) — deploying all content." -Level Warning
    }
    finally {
        Pop-Location
    }
}

function Test-ShouldDeployFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    # Normalise to forward-slash relative path
    $relativePath = $FilePath.Replace('\', '/').Replace($BasePath.Replace('\', '/') + '/', '')

    # Check exclusions from sentinel-deployment.config
    if ($script:DeploymentConfig) {
        $excluded = @()
        if ($script:DeploymentConfig.PSObject.Properties.Name -contains 'excludecontentfiles') {
            $excluded = @($script:DeploymentConfig.excludecontentfiles)
        }
        foreach ($excl in $excluded) {
            if ($relativePath -like "$excl*" -or $relativePath -eq $excl) {
                Write-PipelineMessage "  Excluded by config: $relativePath" -Level Debug
                return $false
            }
        }
    }

    # Smart deployment: check if file was changed
    if ($script:SmartDeploymentActive) {
        $isChanged = $false
        foreach ($cf in $script:ChangedFiles) {
            if ($relativePath -eq $cf -or $relativePath -like "$cf*" -or $cf -like "$relativePath*") {
                $isChanged = $true
                break
            }
        }

        # Also check if the file's parent directory contains any changed files
        # (for watchlists where data.csv or watchlist.json may change)
        if (-not $isChanged) {
            $parentDir = Split-Path $relativePath -Parent
            if ($parentDir) {
                foreach ($cf in $script:ChangedFiles) {
                    if ($cf -like "$parentDir/*") {
                        $isChanged = $true
                        break
                    }
                }
            }
        }

        if (-not $isChanged) {
            # Check deployment state — retry items that failed previously
            if (-not (Test-WasDeployedSuccessfully -FilePath $FilePath)) {
                Write-PipelineMessage "Retrying: $relativePath — not previously deployed successfully" -Level Warning
                return $true  # Not previously deployed successfully — retry
            }
            return $false
        }
    }

    return $true
}

function Get-PrioritizedFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo[]]$Files
    )

    if (-not $script:DeploymentConfig) {
        return $Files
    }

    $prioritized = @()
    if ($script:DeploymentConfig.PSObject.Properties.Name -contains 'prioritizedcontentfiles') {
        $prioritized = @($script:DeploymentConfig.prioritizedcontentfiles)
    }

    if ($prioritized.Count -eq 0) {
        return $Files
    }

    $priorityFiles = @()
    $normalFiles = @()

    foreach ($file in $Files) {
        $relativePath = $file.FullName.Replace('\', '/').Replace($BasePath.Replace('\', '/') + '/', '')
        $isPriority = $false
        foreach ($p in $prioritized) {
            if ($relativePath -eq $p -or $relativePath -like "$p*") {
                $isPriority = $true
                break
            }
        }
        if ($isPriority) {
            $priorityFiles += $file
        }
        else {
            $normalFiles += $file
        }
    }

    return @($priorityFiles) + @($normalFiles)
}

# ---------------------------------------------------------------------------
# Deployment State: Persist successful deployments across pipeline runs so
# that smart deployment can retry items that failed previously without making
# expensive per-item API existence checks.
# File: .deployment-state.json at $BasePath
# Structure: { "deployedItems": { "relative/path": { "lastDeployed": "ISO8601", "status": "success" } } }
# ---------------------------------------------------------------------------
$script:DeploymentState = $null
$script:DeploymentStatePath = $null

function Initialize-DeploymentState {
    [CmdletBinding()]
    param()

    $script:DeploymentStatePath = Join-Path $BasePath ".deployment-state.json"

    if (Test-Path $script:DeploymentStatePath) {
        try {
            $raw = Get-Content -Path $script:DeploymentStatePath -Raw | ConvertFrom-Json
            # Rebuild as a proper hashtable for O(1) lookups
            $script:DeploymentState = @{ deployedItems = @{} }
            if ($raw.PSObject.Properties['deployedItems']) {
                foreach ($prop in $raw.deployedItems.PSObject.Properties) {
                    $script:DeploymentState.deployedItems[$prop.Name] = @{
                        lastDeployed = $prop.Value.lastDeployed
                        status       = $prop.Value.status
                    }
                }
            }
            Write-PipelineMessage "Loaded deployment state: $($script:DeploymentState.deployedItems.Count) previously deployed item(s)." -Level Info
        }
        catch {
            Write-PipelineMessage "Failed to load deployment state: $($_.Exception.Message) — starting fresh." -Level Warning
            $script:DeploymentState = @{ deployedItems = @{} }
        }
    }
    else {
        $script:DeploymentState = @{ deployedItems = @{} }
        Write-PipelineMessage "No deployment state file found — all items will deploy on first run." -Level Info
    }
}

function Save-DeploymentState {
    [CmdletBinding()]
    param()

    if ($null -eq $script:DeploymentState -or $null -eq $script:DeploymentStatePath) {
        return
    }

    try {
        $script:DeploymentState | ConvertTo-Json -Depth 5 | Set-Content -Path $script:DeploymentStatePath -Encoding UTF8
        Write-PipelineMessage "Deployment state saved ($($script:DeploymentState.deployedItems.Count) item(s))." -Level Debug
    }
    catch {
        Write-PipelineMessage "Failed to save deployment state: $($_.Exception.Message)" -Level Warning
    }
}

function Set-DeploymentItemState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
        ,
        [Parameter(Mandatory = $true)]
        [ValidateSet("success", "failed")]
        [string]$Status
    )

    if ($null -eq $script:DeploymentState) {
        return
    }

    $key = $FilePath.Replace('\', '/').Replace($BasePath.Replace('\', '/') + '/', '')

    if ($Status -eq "success") {
        $script:DeploymentState.deployedItems[$key] = @{
            lastDeployed = (Get-Date -Format 'o')
            status       = "success"
        }
    }
    else {
        # Remove the entry so next run will retry
        if ($script:DeploymentState.deployedItems.ContainsKey($key)) {
            $script:DeploymentState.deployedItems.Remove($key)
        }
    }
}

function Test-WasDeployedSuccessfully {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    if ($null -eq $script:DeploymentState) {
        return $false
    }

    $key = $FilePath.Replace('\', '/').Replace($BasePath.Replace('\', '/') + '/', '')

    if ($script:DeploymentState.deployedItems.ContainsKey($key)) {
        return $script:DeploymentState.deployedItems[$key].status -eq "success"
    }

    return $false
}

# ---------------------------------------------------------------------------
# Helper: Write ADO pipeline commands where applicable, otherwise standard output
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# Helper: Invoke REST API with retry logic for transient failures
# ---------------------------------------------------------------------------
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
                Uri     = $Uri
                Method  = $Method
                Headers = $Headers
            }

            if ($Body) {
                $params.Body = $Body
            }

            $response = Invoke-RestMethod @params -ContentType "application/json"
            return $response
        }
        catch {
            $statusCode = $null
            if ($_.Exception.Response) {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            $retryableCodes = @(429, 500, 502, 503, 504)
            if ($statusCode -and $retryableCodes -contains $statusCode -and $attempt -lt $MaxRetries) {
                $delay = $RetryDelaySeconds * $attempt
                Write-PipelineMessage "API call returned $statusCode. Retrying in ${delay}s (attempt $attempt of $MaxRetries)..." -Level Warning
                Start-Sleep -Seconds $delay
                continue
            }

            # PowerShell 7: error body is in ErrorDetails.Message
            $errorDetail = $_.Exception.Message
            if ($_.ErrorDetails.Message) {
                $errorDetail = "HTTP $statusCode - $($_.ErrorDetails.Message)"
            }
            elseif ($_.Exception.Response) {
                try {
                    $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                    $responseBody = $reader.ReadToEnd()
                    $reader.Close()
                    $errorDetail = "HTTP $statusCode - $responseBody"
                }
                catch {
                    $errorDetail = "HTTP $statusCode - $($_.Exception.Message)"
                }
            }

            throw "API call failed: $errorDetail"
        }
    }
}

# ---------------------------------------------------------------------------
# Authentication
# ---------------------------------------------------------------------------
function Connect-AzureEnvironment {
    [CmdletBinding()]
    param()

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

    if ($script:SubscriptionId) {
        Set-AzContext -SubscriptionId $script:SubscriptionId -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null
        $context = Get-AzContext -WarningAction SilentlyContinue
    }
    else {
        $script:SubscriptionId = $context.Subscription.Id
    }

    Write-PipelineMessage "Authenticated to subscription: $($context.Subscription.Id) ($($context.Subscription.Name))" -Level Success

    $script:ServerUrl = if ($IsGov) {
        "https://management.usgovcloudapi.net"
    }
    else {
        "https://management.azure.com"
    }

    $script:BaseUri = "$($script:ServerUrl)/subscriptions/$($script:SubscriptionId)/resourceGroups/$ResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$Workspace"

    $script:WorkspaceResourceId = "/subscriptions/$($script:SubscriptionId)/resourceGroups/$ResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$Workspace"

    $script:PlaybookRG = if ($PlaybookResourceGroup) { $PlaybookResourceGroup } else { $ResourceGroup }

    $resourceEndpoint = $script:ServerUrl
    try {
        $tokenResponse = Get-AzAccessToken -ResourceUrl $resourceEndpoint -ErrorAction Stop -WarningAction SilentlyContinue

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

    $script:AuthHeader = @{
        'Content-Type'  = 'application/json'
        'Authorization' = "Bearer $accessToken"
    }

    Write-PipelineMessage "Target workspace: $Workspace (Resource Group: $ResourceGroup, Region: $Region)" -Level Info
    if ($script:PlaybookRG -ne $ResourceGroup) {
        Write-PipelineMessage "Playbooks will deploy to resource group: $($script:PlaybookRG)" -Level Info
    }
    if ($IsGov) {
        Write-PipelineMessage "Azure Government cloud mode enabled." -Level Info
    }

    # Retrieve the workspace ID (GUID) for playbook parameter injection
    try {
        $wsUri = "$($script:ServerUrl)/subscriptions/$($script:SubscriptionId)/resourceGroups/$ResourceGroup/providers/Microsoft.OperationalInsights/workspaces/${Workspace}?api-version=2022-10-01"
        $wsResponse = Invoke-SentinelApi -Uri $wsUri -Method Get -Headers $script:AuthHeader
        $script:WorkspaceId = $wsResponse.properties.customerId
        Write-PipelineMessage "Workspace ID: $($script:WorkspaceId)" -Level Info
    }
    catch {
        Write-PipelineMessage "Could not retrieve workspace ID: $($_.Exception.Message)" -Level Warning
        $script:WorkspaceId = $null
    }
}

# ---------------------------------------------------------------------------
# Dependency Graph: Load, Validate, and Check Prerequisites
# ---------------------------------------------------------------------------
$script:DependencyGraph = @{}
$script:WorkspaceTables = @()
$script:WorkspaceWatchlists = @()
$script:WorkspaceFunctions = @()

function Initialize-DependencyGraph {
    [CmdletBinding()]
    param()

    $depsFile = Join-Path $BasePath "dependencies.json"

    if (-not (Test-Path $depsFile)) {
        Write-PipelineMessage "No dependencies.json found — all content will deploy unconditionally." -Level Info
        return
    }

    Write-PipelineMessage "Loading dependency graph..." -Level Section

    try {
        $depsJson = Get-Content -Path $depsFile -Raw | ConvertFrom-Json
        $deps = $depsJson.dependencies

        # Convert PSObject properties to hashtable
        foreach ($prop in $deps.PSObject.Properties) {
            $entry = @{}
            $val = $prop.Value
            $valProps = @($val.PSObject.Properties.Name)
            if ($valProps -contains 'tables')       { $entry.tables       = @($val.tables) }
            if ($valProps -contains 'watchlists')   { $entry.watchlists   = @($val.watchlists) }
            if ($valProps -contains 'functions')    { $entry.functions    = @($val.functions) }
            if ($valProps -contains 'externalData') { $entry.externalData = @($val.externalData) }
            if ($valProps -contains 'playbooks')    { $entry.playbooks    = @($val.playbooks) }
            $script:DependencyGraph[$prop.Name] = $entry
        }

        Write-PipelineMessage "Loaded dependencies for $($script:DependencyGraph.Count) content items." -Level Info
    }
    catch {
        Write-PipelineMessage "Failed to parse dependencies.json: $($_.Exception.Message)" -Level Warning
        Write-PipelineMessage "Continuing without dependency checks." -Level Warning
    }
}

function Invoke-PreFlightChecks {
    [CmdletBinding()]
    param()

    if ($script:DependencyGraph.Count -eq 0) {
        return
    }

    Write-PipelineMessage "Running pre-flight dependency checks..." -Level Section

    # Bulk-fetch workspace tables (single API call)
    try {
        $tablesUri = "$($script:ServerUrl)/subscriptions/$($script:SubscriptionId)/resourceGroups/$ResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$Workspace/tables?api-version=2022-10-01"
        $tablesResponse = Invoke-SentinelApi -Uri $tablesUri -Method Get -Headers $script:AuthHeader
        $script:WorkspaceTables = @($tablesResponse.value | ForEach-Object { $_.name })
        Write-PipelineMessage "  Workspace has $($script:WorkspaceTables.Count) tables." -Level Info
    }
    catch {
        Write-PipelineMessage "  Failed to list workspace tables: $($_.Exception.Message)" -Level Warning
        Write-PipelineMessage "  Table dependency checks will be skipped." -Level Warning
    }

    # Bulk-fetch workspace watchlists (single API call)
    try {
        $watchlistsUri = "$($script:BaseUri)/providers/Microsoft.SecurityInsights/watchlists?api-version=$($script:SentinelApiVersion)"
        $watchlistsResponse = Invoke-SentinelApi -Uri $watchlistsUri -Method Get -Headers $script:AuthHeader
        $script:WorkspaceWatchlists = @($watchlistsResponse.value |
            Where-Object { $_.properties -and (-not ($_.properties.PSObject.Properties.Name -contains 'isDeleted' -and $_.properties.isDeleted)) } |
            Where-Object { $_.properties.PSObject.Properties.Name -contains 'watchlistAlias' } |
            ForEach-Object { $_.properties.watchlistAlias })
        Write-PipelineMessage "  Workspace has $($script:WorkspaceWatchlists.Count) watchlists." -Level Info
    }
    catch {
        Write-PipelineMessage "  Failed to list workspace watchlists: $($_.Exception.Message)" -Level Warning
        Write-PipelineMessage "  Watchlist dependency checks will be skipped." -Level Warning
    }

    # Bulk-fetch workspace saved searches to find functions (single API call)
    try {
        $savedSearchUri = "$($script:ServerUrl)/subscriptions/$($script:SubscriptionId)/resourceGroups/$ResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$Workspace/savedSearches?api-version=$($script:SavedSearchApiVersion)"
        $savedSearchResponse = Invoke-SentinelApi -Uri $savedSearchUri -Method Get -Headers $script:AuthHeader
        $script:WorkspaceFunctions = @($savedSearchResponse.value |
            Where-Object { $_.properties.PSObject.Properties.Name -contains 'functionAlias' -and $_.properties.functionAlias } |
            ForEach-Object { $_.properties.functionAlias })
        Write-PipelineMessage "  Workspace has $($script:WorkspaceFunctions.Count) functions/parsers." -Level Info
    }
    catch {
        Write-PipelineMessage "  Failed to list workspace functions: $($_.Exception.Message)" -Level Warning
        Write-PipelineMessage "  Function dependency checks will be skipped." -Level Warning
    }

    # Build list of internal parsers we're about to deploy
    $parsersPath = Join-Path $BasePath "Parsers"
    $script:InternalParsers = @()
    if (Test-Path $parsersPath) {
        $parserFiles = @(Get-ChildItem -Path $parsersPath -Include "*.yaml", "*.yml" -Recurse -File)
        foreach ($pf in $parserFiles) {
            try {
                $content = Get-Content -Path $pf.FullName -Raw
                $parsed = ConvertFrom-Yaml -Yaml $content
                if ($parsed.ContainsKey('functionAlias')) {
                    $script:InternalParsers += $parsed['functionAlias']
                }
            }
            catch { }
        }
    }

    # Build list of internal watchlist aliases we're about to deploy
    $watchlistsPath = Join-Path $BasePath "Watchlists"
    $script:InternalWatchlists = @()
    if (Test-Path $watchlistsPath) {
        $wlDirs = @(Get-ChildItem -Path $watchlistsPath -Directory)
        foreach ($wlDir in $wlDirs) {
            $wlJson = Join-Path $wlDir.FullName "watchlist.json"
            if (Test-Path $wlJson) {
                try {
                    $wlMeta = Get-Content -Path $wlJson -Raw | ConvertFrom-Json
                    if ($wlMeta.watchlistAlias) {
                        $script:InternalWatchlists += $wlMeta.watchlistAlias
                    }
                }
                catch { }
            }
        }
    }

    Write-PipelineMessage "  Internal parsers to deploy: $($script:InternalParsers -join ', ')" -Level Info
    Write-PipelineMessage "  Internal watchlists to deploy: $($script:InternalWatchlists -join ', ')" -Level Info
    Write-PipelineMessage "Pre-flight checks complete." -Level Success
}

function Test-ContentDependencies {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ContentPath
    )

    # No dependency graph loaded — deploy everything
    if ($script:DependencyGraph.Count -eq 0) {
        return @{ Passed = $true; Missing = @() }
    }

    # Normalise path to use forward slashes and make relative
    $relativePath = $ContentPath.Replace('\', '/').Replace($BasePath.Replace('\', '/') + '/', '')

    # No entry in dependencies — no prerequisites, deploy unconditionally
    if (-not $script:DependencyGraph.ContainsKey($relativePath)) {
        return @{ Passed = $true; Missing = @() }
    }

    $deps = $script:DependencyGraph[$relativePath]
    $missing = @()

    # Check table dependencies
    if ($deps.ContainsKey('tables') -and $script:WorkspaceTables.Count -gt 0) {
        foreach ($table in $deps.tables) {
            if ($script:WorkspaceTables -notcontains $table) {
                $missing += "table:$table"
            }
        }
    }

    # Check watchlist dependencies — satisfied by workspace OR internal repo watchlists
    if ($deps.ContainsKey('watchlists')) {
        foreach ($wl in $deps.watchlists) {
            $inWorkspace = $script:WorkspaceWatchlists -contains $wl
            $inRepo = $script:InternalWatchlists -contains $wl
            if (-not $inWorkspace -and -not $inRepo) {
                $missing += "watchlist:$wl"
            }
        }
    }

    # Check function dependencies — satisfied by workspace OR internal repo parsers
    if ($deps.ContainsKey('functions')) {
        foreach ($fn in $deps.functions) {
            $inWorkspace = $script:WorkspaceFunctions -contains $fn
            $inRepo = $script:InternalParsers -contains $fn
            if (-not $inWorkspace -and -not $inRepo) {
                $missing += "function:$fn"
            }
        }
    }

    return @{
        Passed  = ($missing.Count -eq 0)
        Missing = $missing
    }
}

# ---------------------------------------------------------------------------
# Deploy Custom Parsers (KQL Functions from YAML)
# ---------------------------------------------------------------------------
function Deploy-CustomParsers {
    [CmdletBinding()]
    param()

    $counters = @{ Deployed = 0; Skipped = 0; Failed = 0 }
    $parsersPath = Join-Path $BasePath "Parsers"

    Write-PipelineMessage "Deploying KQL parsers/functions..." -Level Section

    if (-not (Test-Path $parsersPath)) {
        Write-PipelineMessage "Parsers folder not found at '$parsersPath' — skipping." -Level Warning
        return $counters
    }

    if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
        Write-PipelineMessage "Installing powershell-yaml module..." -Level Info
        Install-Module -Name powershell-yaml -Force -Scope CurrentUser
    }
    Import-Module powershell-yaml -ErrorAction Stop

    $yamlFiles = @(Get-ChildItem -Path $parsersPath -Include "*.yaml", "*.yml" -Recurse -File)
    if ($yamlFiles.Count -eq 0) {
        Write-PipelineMessage "No YAML files found in '$parsersPath' — skipping." -Level Info
        return $counters
    }

    $yamlFiles = @(Get-PrioritizedFiles -Files $yamlFiles)
    Write-PipelineMessage "Found $($yamlFiles.Count) parser(s) to process." -Level Info

    foreach ($file in $yamlFiles) {
        if (-not (Test-ShouldDeployFile -FilePath $file.FullName)) {
            Write-PipelineMessage "Unchanged: $($file.Name) — skipping (smart deployment)" -Level Info
            $counters.Skipped++
            continue
        }
        try {
            $yamlContent = Get-Content -Path $file.FullName -Raw
            $parser = ConvertFrom-Yaml -Yaml $yamlContent

            # Validate required fields
            $requiredFields = @('id', 'name', 'functionAlias', 'query')
            $missingFields = @($requiredFields | Where-Object { -not $parser.ContainsKey($_) -or [string]::IsNullOrWhiteSpace($parser[$_]) })
            if ($missingFields.Count -gt 0) {
                Write-PipelineMessage "Skipping '$($file.Name)': missing required fields: $($missingFields -join ', ')" -Level Warning
                $counters.Skipped++
                continue
            }

            $parserId = $parser['id']
            $parserName = $parser['name']
            $functionAlias = $parser['functionAlias']

            Write-PipelineMessage "Processing: $parserName [alias: $functionAlias]" -Level Info

            $properties = @{
                category     = if ($parser.ContainsKey('category')) { $parser['category'] } else { "Sentinel Parsers" }
                displayName  = $parserName
                query        = $parser['query']
                functionAlias = $functionAlias
                version      = 2
            }

            if ($parser.ContainsKey('functionParameters') -and -not [string]::IsNullOrWhiteSpace($parser['functionParameters'])) {
                $properties.functionParameters = $parser['functionParameters']
            }

            $body = @{
                etag       = "*"
                properties = $properties
            } | ConvertTo-Json -Depth 10

            $uri = "$($script:ServerUrl)/subscriptions/$($script:SubscriptionId)/resourceGroups/$ResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$Workspace/savedSearches/$($parserId)?api-version=$($script:SavedSearchApiVersion)"

            if ($WhatIf) {
                Write-PipelineMessage "[WhatIf] Would deploy parser: $parserName [alias: $functionAlias]" -Level Info
                $counters.Deployed++
            }
            else {
                Invoke-SentinelApi -Uri $uri -Method Put -Headers $script:AuthHeader -Body $body | Out-Null
                Write-PipelineMessage "Deployed: $parserName [alias: $functionAlias]" -Level Success
                $counters.Deployed++
                Set-DeploymentItemState -FilePath $file.FullName -Status "success"
            }
        }
        catch {
            Write-PipelineMessage "Failed to deploy parser '$($file.Name)': $($_.Exception.Message)" -Level Error
            $counters.Failed++
            Set-DeploymentItemState -FilePath $file.FullName -Status "failed"
        }
    }

    return $counters
}

# ---------------------------------------------------------------------------
# Deploy Custom Detections (Analytics Rules from YAML)
# ---------------------------------------------------------------------------
function Deploy-CustomDetections {
    [CmdletBinding()]
    param()

    $counters = @{ Deployed = 0; Skipped = 0; Failed = 0 }
    $detectionsPath = Join-Path $BasePath "AnalyticalRules"

    Write-PipelineMessage "Deploying custom analytics rules..." -Level Section

    if (-not (Test-Path $detectionsPath)) {
        Write-PipelineMessage "AnalyticalRules folder not found at '$detectionsPath' — skipping." -Level Warning
        return $counters
    }

    # Ensure powershell-yaml is available
    if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
        Write-PipelineMessage "Installing powershell-yaml module..." -Level Info
        Install-Module -Name powershell-yaml -Force -Scope CurrentUser
    }
    Import-Module powershell-yaml -ErrorAction Stop

    $yamlFiles = @(Get-ChildItem -Path $detectionsPath -Include "*.yaml", "*.yml" -Recurse -File)
    if ($yamlFiles.Count -eq 0) {
        Write-PipelineMessage "No YAML files found in '$detectionsPath' — skipping." -Level Info
        return $counters
    }

    $yamlFiles = @(Get-PrioritizedFiles -Files $yamlFiles)
    Write-PipelineMessage "Found $($yamlFiles.Count) detection file(s) to process." -Level Info

    foreach ($file in $yamlFiles) {
        if (-not (Test-ShouldDeployFile -FilePath $file.FullName)) {
            Write-PipelineMessage "Unchanged: $($file.Name) — skipping (smart deployment)" -Level Info
            $counters.Skipped++
            continue
        }
        try {
            $yamlContent = Get-Content -Path $file.FullName -Raw
            $rule = ConvertFrom-Yaml -Yaml $yamlContent

            # Validate required fields
            $requiredFields = @('id', 'name', 'kind', 'severity', 'query')
            $missingFields = @($requiredFields | Where-Object { -not $rule.ContainsKey($_) -or [string]::IsNullOrWhiteSpace($rule[$_]) })
            if ($missingFields.Count -gt 0) {
                Write-PipelineMessage "Skipping '$($file.Name)': missing required fields: $($missingFields -join ', ')" -Level Warning
                $counters.Skipped++
                continue
            }

            $ruleId = $rule['id']
            $ruleName = $rule['name']
            $ruleKind = $rule['kind']

            # Check dependency graph — deploy disabled if prerequisites are not met
            $depCheck = Test-ContentDependencies -ContentPath $file.FullName
            $missingDeps = $false
            if (-not $depCheck.Passed) {
                Write-PipelineMessage "Missing dependencies for '$($file.Name)': $($depCheck.Missing -join ', ') — deploying as disabled" -Level Warning
                $missingDeps = $true
            }

            Write-PipelineMessage "Processing: $ruleName ($ruleKind) [$($file.Name)]" -Level Info

            # Build the API properties — force disabled if dependencies are missing
            $ruleDescription = if ($rule.ContainsKey('description')) { $rule['description'] } else { "" }
            $ruleEnabled     = if ($missingDeps) { $false } elseif ($rule.ContainsKey('enabled')) { [bool]$rule['enabled'] } else { $true }

            $properties = @{
                displayName       = $ruleName
                description       = $ruleDescription
                severity          = $rule['severity']
                enabled           = $ruleEnabled
                query             = $rule['query']
                suppressionEnabled  = if ($rule.ContainsKey('suppressionEnabled')) { [bool]$rule['suppressionEnabled'] } else { $false }
                suppressionDuration = if ($rule.ContainsKey('suppressionDuration')) { $rule['suppressionDuration'] } else { "PT5H" }
            }

            # Scheduled-specific fields
            if ($ruleKind -eq "Scheduled") {
                $scheduledFields = @('queryFrequency', 'queryPeriod', 'triggerOperator', 'triggerThreshold')
                $missingScheduled = @($scheduledFields | Where-Object { -not $rule.ContainsKey($_) })
                if ($missingScheduled.Count -gt 0) {
                    Write-PipelineMessage "Skipping '$ruleName': Scheduled rule missing required fields: $($missingScheduled -join ', ')" -Level Warning
                    $counters.Skipped++
                    continue
                }

                $properties.queryFrequency  = $rule['queryFrequency']
                $properties.queryPeriod     = $rule['queryPeriod']
                $properties.triggerThreshold = [int]$rule['triggerThreshold']

                # Map style guide shorthand (gt, lt, eq) to API values
                $operatorMap = @{
                    'gt' = 'GreaterThan'; 'greaterthan' = 'GreaterThan'
                    'lt' = 'LessThan';    'lessthan'    = 'LessThan'
                    'eq' = 'Equal';       'equal'       = 'Equal'
                    'ne' = 'NotEqual';    'notequal'    = 'NotEqual'
                }
                $rawOperator = $rule['triggerOperator'].ToLower()
                $properties.triggerOperator = if ($operatorMap.ContainsKey($rawOperator)) { $operatorMap[$rawOperator] } else { $rule['triggerOperator'] }
            }

            # Optional fields — support both 'techniques' and 'relevantTechniques' (Azure-Sentinel repo uses the latter)
            if ($rule.ContainsKey('tactics')) {
                $properties.tactics = [array]$rule['tactics']
            }
            $techKey = if ($rule.ContainsKey('relevantTechniques')) { 'relevantTechniques' } elseif ($rule.ContainsKey('techniques')) { 'techniques' } else { $null }
            if ($techKey) {
                $allTechniques = [array]$rule[$techKey]
                # Parent techniques (T####) go in 'techniques'
                $properties.techniques = [array]($allTechniques | ForEach-Object { ($_ -split '\.')[0] } | Select-Object -Unique)
                # Sub-techniques (T####.###) go in 'subTechniques' (preview API)
                $subTechs = @($allTechniques | Where-Object { $_ -match '\.' } | Select-Object -Unique)
                if ($subTechs -and $subTechs.Count -gt 0) {
                    $properties.subTechniques = $subTechs
                }
            }
            if ($rule.ContainsKey('entityMappings')) {
                $properties.entityMappings = [array]$rule['entityMappings']
            }
            if ($rule.ContainsKey('sentinelEntitiesMappings')) {
                $properties.sentinelEntitiesMappings = [array]$rule['sentinelEntitiesMappings']
            }
            if ($rule.ContainsKey('customDetails')) {
                $properties.customDetails = $rule['customDetails']
            }
            if ($rule.ContainsKey('alertDetailsOverride')) {
                $properties.alertDetailsOverride = $rule['alertDetailsOverride']
            }
            if ($rule.ContainsKey('eventGroupingSettings')) {
                $properties.eventGroupingSettings = $rule['eventGroupingSettings']
            }
            if ($rule.ContainsKey('incidentConfiguration')) {
                $properties.incidentConfiguration = $rule['incidentConfiguration']
            }

            $body = @{
                kind       = $ruleKind
                properties = $properties
            } | ConvertTo-Json -Depth 20

            $uri = "$($script:BaseUri)/providers/Microsoft.SecurityInsights/alertRules/$($ruleId)?api-version=$($script:SentinelApiVersion)"

            if ($WhatIf) {
                Write-PipelineMessage "[WhatIf] Would deploy detection: $ruleName ($ruleKind, $($rule['severity']))" -Level Info
                $counters.Deployed++
            }
            else {
                Invoke-SentinelApi -Uri $uri -Method Put -Headers $script:AuthHeader -Body $body | Out-Null
                $deployMsg = if ($missingDeps) { "Deployed (disabled — missing deps): $ruleName" } else { "Deployed: $ruleName" }
                Write-PipelineMessage $deployMsg -Level Success
                $counters.Deployed++
                Set-DeploymentItemState -FilePath $file.FullName -Status "success"
            }
        }
        catch {
            $errorMsg = $_.Exception.Message
            $isKqlError = $errorMsg -match 'FailedToResolveColumn|FailedToResolveScalarExpression|SemanticError|could not be found|Failed to run the analytics rule query'

            if ($missingDeps) {
                Write-PipelineMessage "Cannot deploy '$($file.Name)' even as disabled — $errorMsg" -Level Warning
                $counters.Skipped++
            }
            elseif ($isKqlError -and $ruleEnabled) {
                # KQL validation failed (e.g. newly deployed watchlist columns not yet queryable).
                # Retry with enabled=false so the rule is created and can be enabled later.
                Write-PipelineMessage "KQL validation error for '$($file.Name)' — retrying as disabled..." -Level Warning
                try {
                    $properties.enabled = $false
                    $retryBody = @{
                        kind       = $ruleKind
                        properties = $properties
                    } | ConvertTo-Json -Depth 20
                    Invoke-SentinelApi -Uri $uri -Method Put -Headers $script:AuthHeader -Body $retryBody | Out-Null
                    Write-PipelineMessage "Deployed (disabled — KQL validation): $ruleName" -Level Success
                    $counters.Deployed++
                    Set-DeploymentItemState -FilePath $file.FullName -Status "success"
                }
                catch {
                    Write-PipelineMessage "Failed to deploy '$($file.Name)' even as disabled: $($_.Exception.Message)" -Level Error
                    $counters.Failed++
                    Set-DeploymentItemState -FilePath $file.FullName -Status "failed"
                }
            }
            else {
                Write-PipelineMessage "Failed to deploy '$($file.Name)': $errorMsg" -Level Error
                $counters.Failed++
                Set-DeploymentItemState -FilePath $file.FullName -Status "failed"
            }
        }
    }

    return $counters
}

# ---------------------------------------------------------------------------
# Deploy Custom Watchlists (JSON metadata + CSV data)
# ---------------------------------------------------------------------------
function Deploy-CustomWatchlists {
    [CmdletBinding()]
    param()

    $counters = @{ Deployed = 0; Skipped = 0; Failed = 0 }
    $watchlistsPath = Join-Path $BasePath "Watchlists"

    Write-PipelineMessage "Deploying custom watchlists..." -Level Section

    if (-not (Test-Path $watchlistsPath)) {
        Write-PipelineMessage "Watchlists folder not found at '$watchlistsPath' — skipping." -Level Warning
        return $counters
    }

    $watchlistDirs = @(Get-ChildItem -Path $watchlistsPath -Directory)
    if ($watchlistDirs.Count -eq 0) {
        Write-PipelineMessage "No watchlist subfolders found — skipping." -Level Info
        return $counters
    }

    Write-PipelineMessage "Found $($watchlistDirs.Count) watchlist(s) to process." -Level Info

    foreach ($dir in $watchlistDirs) {
        try {
            $metadataPath = Join-Path $dir.FullName "watchlist.json"
            $csvPath = Join-Path $dir.FullName "data.csv"

            if (-not (Test-ShouldDeployFile -FilePath $metadataPath) -and -not (Test-ShouldDeployFile -FilePath $csvPath)) {
                Write-PipelineMessage "Unchanged: $($dir.Name) — skipping (smart deployment)" -Level Info
                $counters.Skipped++
                continue
            }

            if (-not (Test-Path $metadataPath)) {
                Write-PipelineMessage "Skipping '$($dir.Name)': watchlist.json not found." -Level Warning
                $counters.Skipped++
                continue
            }

            if (-not (Test-Path $csvPath)) {
                Write-PipelineMessage "Skipping '$($dir.Name)': data.csv not found." -Level Warning
                $counters.Skipped++
                continue
            }

            $metadata = Get-Content -Path $metadataPath -Raw | ConvertFrom-Json
            $csvContent = Get-Content -Path $csvPath -Raw

            # Validate required metadata fields
            if (-not $metadata.watchlistAlias -or -not $metadata.displayName -or -not $metadata.itemsSearchKey) {
                Write-PipelineMessage "Skipping '$($dir.Name)': watchlist.json missing required fields (watchlistAlias, displayName, itemsSearchKey)." -Level Warning
                $counters.Skipped++
                continue
            }

            # Check CSV file size (3.5 MB limit for inline upload)
            $csvSize = (Get-Item $csvPath).Length
            if ($csvSize -gt 3.5MB) {
                Write-PipelineMessage "Skipping '$($dir.Name)': data.csv exceeds 3.5 MB inline upload limit ($([math]::Round($csvSize / 1MB, 2)) MB)." -Level Warning
                $counters.Skipped++
                continue
            }

            $alias = $metadata.watchlistAlias

            # Check dependency graph
            $depCheck = Test-ContentDependencies -ContentPath $metadataPath
            if (-not $depCheck.Passed) {
                Write-PipelineMessage "Skipping '$($dir.Name)': missing dependencies — $($depCheck.Missing -join ', ')" -Level Warning
                $counters.Skipped++
                continue
            }

            Write-PipelineMessage "Processing watchlist: $($metadata.displayName) (alias: $alias)" -Level Info

            $body = @{
                properties = @{
                    watchlistAlias    = $alias
                    displayName       = $metadata.displayName
                    description       = if ($metadata.description) { $metadata.description } else { "" }
                    provider          = if ($metadata.provider) { $metadata.provider } else { "Custom" }
                    source            = "Local File"
                    sourceType        = "Local"
                    itemsSearchKey    = $metadata.itemsSearchKey
                    contentType       = "Text/Csv"
                    rawContent        = $csvContent
                    numberOfLinesToSkip = 0
                }
            } | ConvertTo-Json -Depth 10

            $uri = "$($script:BaseUri)/providers/Microsoft.SecurityInsights/watchlists/$($alias)?api-version=$($script:SentinelApiVersion)"

            if ($WhatIf) {
                $rowCount = @($csvContent -split "`n" | Where-Object { $_.Trim() }).Count - 1
                Write-PipelineMessage "[WhatIf] Would deploy watchlist: $($metadata.displayName) ($rowCount rows)" -Level Info
                $counters.Deployed++
            }
            else {
                Invoke-SentinelApi -Uri $uri -Method Put -Headers $script:AuthHeader -Body $body | Out-Null
                Write-PipelineMessage "Deployed: $($metadata.displayName)" -Level Success
                $counters.Deployed++
                Set-DeploymentItemState -FilePath $metadataPath -Status "success"
            }
        }
        catch {
            Write-PipelineMessage "Failed to deploy watchlist '$($dir.Name)': $($_.Exception.Message)" -Level Error
            $counters.Failed++
            Set-DeploymentItemState -FilePath $metadataPath -Status "failed"
        }
    }

    return $counters
}

# ---------------------------------------------------------------------------
# Deploy Custom Playbooks (ARM templates)
# ---------------------------------------------------------------------------
function Deploy-CustomPlaybooks {
    [CmdletBinding()]
    param()

    $counters = @{ Deployed = 0; Skipped = 0; Failed = 0 }
    $playbooksPath = Join-Path $BasePath "Playbooks"

    Write-PipelineMessage "Deploying custom playbooks..." -Level Section

    if (-not (Test-Path $playbooksPath)) {
        Write-PipelineMessage "Playbooks folder not found at '$playbooksPath' — skipping." -Level Warning
        return $counters
    }

    # Find all ARM template JSON files recursively (exclude parameters files, README, .DS_Store, Template folder)
    $templateFiles = @(Get-ChildItem -Path $playbooksPath -Filter "*.json" -Recurse |
        Where-Object { $_.Name -notmatch '\.parameters\.json$' -and $_.Name -ne '.DS_Store' -and $_.Directory.Name -ne 'Template' })
    if ($templateFiles.Count -eq 0) {
        Write-PipelineMessage "No playbook ARM templates found — skipping." -Level Info
        return $counters
    }

    Write-PipelineMessage "Found $($templateFiles.Count) playbook(s) to process." -Level Info

    # Deploy Module playbooks first — other playbooks reference them as child workflows.
    # Within Module/, sort so modules that reference other modules deploy last.
    $moduleFiles = @($templateFiles | Where-Object { $_.Directory.Name -eq 'Module' })
    $nonModuleFiles = @($templateFiles | Where-Object { $_.Directory.Name -ne 'Module' })

    # Split modules into leaf (no module deps) and dependent (references other modules)
    $leafModules = @()
    $dependentModules = @()
    foreach ($mf in $moduleFiles) {
        $content = Get-Content -Path $mf.FullName -Raw
        $ownName = "Module-$($mf.BaseName)"
        $refs = @([regex]::Matches($content, 'Module-[A-Za-z]+') | ForEach-Object { $_.Value } | Where-Object { $_ -ne $ownName } | Select-Object -Unique)
        if ($refs.Count -gt 0) {
            $dependentModules += $mf
        }
        else {
            $leafModules += $mf
        }
    }

    $orderedFiles = @($leafModules) + @($dependentModules) + @($nonModuleFiles)

    if ($moduleFiles.Count -gt 0) {
        Write-PipelineMessage "  Deploying $($moduleFiles.Count) Module playbook(s) first ($($leafModules.Count) leaf, $($dependentModules.Count) dependent)." -Level Info
    }

    # Build a map of known ARM parameter names to inject from pipeline context
    $knownParams = @{
        'AutomationResourceGroup'   = $script:PlaybookRG
        'SentinelResourceGroup'     = $ResourceGroup
        'SentinelResourceGroupName' = $ResourceGroup
        'PlaybookResourceGroup'     = $script:PlaybookRG
        'SentinelWorkpaceName'      = $Workspace   # Typo in many ARM templates
        'SentinelWorkspaceName'     = $Workspace
        'SubscriptionId'            = $script:SubscriptionId
    }
    if ($script:WorkspaceId) {
        $knownParams['WorkspaceId'] = $script:WorkspaceId
    }

    foreach ($templateFile in $orderedFiles) {
        try {
            if (-not (Test-ShouldDeployFile -FilePath $templateFile.FullName)) {
                Write-PipelineMessage "Unchanged: $($templateFile.Name) — skipping (smart deployment)" -Level Info
                $counters.Skipped++
                continue
            }

            $templatePath = $templateFile.FullName
            $parametersPath = Join-Path $templateFile.DirectoryName "$($templateFile.BaseName).parameters.json"
            $playbookName = $templateFile.BaseName

            # Validate it's an ARM template by checking for the schema property
            $templateContent = Get-Content -Path $templatePath -Raw | ConvertFrom-Json -ErrorAction Stop
            if (-not $templateContent.'$schema' -or $templateContent.'$schema' -notmatch 'deploymentTemplate') {
                Write-PipelineMessage "Skipping '$($templateFile.Name)': not an ARM deployment template." -Level Warning
                $counters.Skipped++
                continue
            }

            $categoryFolder = $templateFile.Directory.Name
            $displayName = if ($categoryFolder -eq "Playbooks") { $playbookName } else { "$categoryFolder/$playbookName" }

            # Check dependency graph
            $depCheck = Test-ContentDependencies -ContentPath $templateFile.FullName
            if (-not $depCheck.Passed) {
                Write-PipelineMessage "Skipping '$displayName': missing dependencies — $($depCheck.Missing -join ', ')" -Level Warning
                $counters.Skipped++
                continue
            }

            Write-PipelineMessage "Processing playbook: $displayName" -Level Info

            $timestamp = Get-Date -Format 'yyyyMMddHHmmss'
            $maxNameLen = 64 - 10 - $timestamp.Length  # "Playbook-" (9) + "-" (1) + timestamp (14)
            $truncatedName = if ($playbookName.Length -gt $maxNameLen) { $playbookName.Substring(0, $maxNameLen) } else { $playbookName }
            $deploymentName = "Playbook-$truncatedName-$timestamp"

            $deployParams = @{
                ResourceGroupName = $script:PlaybookRG
                TemplateFile      = $templatePath
                Name              = $deploymentName
            }

            if (Test-Path $parametersPath) {
                $deployParams.TemplateParameterFile = $parametersPath
                Write-PipelineMessage "  Using parameters file: $($templateFile.BaseName).parameters.json" -Level Debug
            }

            # Auto-inject known parameters that the ARM template expects
            $templateParams = $templateContent.parameters
            if ($templateParams) {
                $templateParamNames = @($templateParams.PSObject.Properties.Name)
                foreach ($paramName in $templateParamNames) {
                    if ($knownParams.ContainsKey($paramName)) {
                        $deployParams[$paramName] = $knownParams[$paramName]
                        Write-PipelineMessage "  Injected parameter: $paramName = $($knownParams[$paramName])" -Level Debug
                    }
                }
            }

            if ($WhatIf) {
                Write-PipelineMessage "[WhatIf] Would deploy playbook: $displayName" -Level Info
                try {
                    Test-AzResourceGroupDeployment @deployParams -ErrorAction Stop | Out-Null
                    Write-PipelineMessage "[WhatIf] Template validation passed for '$displayName'." -Level Success
                }
                catch {
                    Write-PipelineMessage "[WhatIf] Template validation failed for '$displayName': $($_.Exception.Message)" -Level Warning
                }
                $counters.Deployed++
            }
            else {
                $deployment = New-AzResourceGroupDeployment @deployParams -ErrorAction Stop
                Write-PipelineMessage "Deployed: $displayName" -Level Success
                $counters.Deployed++
                Set-DeploymentItemState -FilePath $templateFile.FullName -Status "success"

                # Tag Logic App resources with Source = Sentinel-As-Code (API connections don't support tags reliably)
                try {
                    $deployedResources = Get-AzResourceGroupDeployment -ResourceGroupName $script:PlaybookRG -Name $deploymentName -ErrorAction Stop
                    if ($deployedResources.OutputResources) {
                        foreach ($res in $deployedResources.OutputResources) {
                            if ($res.Id -match 'Microsoft\.Logic/workflows') {
                                $resource = Get-AzResource -ResourceId $res.Id -ErrorAction SilentlyContinue
                                if ($resource) {
                                    $tags = $resource.Tags ?? @{}
                                    $tags['Source'] = 'Sentinel-As-Code'
                                    Set-AzResource -ResourceId $res.Id -Tag $tags -Force -ErrorAction SilentlyContinue | Out-Null
                                }
                            }
                        }
                    }
                }
                catch {
                    Write-PipelineMessage "  Warning: Could not tag resources for '$displayName': $($_.Exception.Message)" -Level Warning
                }
            }
        }
        catch {
            Write-PipelineMessage "Failed to deploy playbook '$displayName': $($_.Exception.Message)" -Level Error
            $counters.Failed++
            Set-DeploymentItemState -FilePath $templateFile.FullName -Status "failed"
        }
    }

    return $counters
}

# ---------------------------------------------------------------------------
# Deploy Custom Workbooks (Gallery template JSON)
# ---------------------------------------------------------------------------
function Deploy-CustomWorkbooks {
    [CmdletBinding()]
    param()

    $counters = @{ Deployed = 0; Skipped = 0; Failed = 0 }
    $workbooksPath = Join-Path $BasePath "Workbooks"

    Write-PipelineMessage "Deploying custom workbooks..." -Level Section

    if (-not (Test-Path $workbooksPath)) {
        Write-PipelineMessage "Workbooks folder not found at '$workbooksPath' — skipping." -Level Warning
        return $counters
    }

    $workbookDirs = @(Get-ChildItem -Path $workbooksPath -Directory)
    if ($workbookDirs.Count -eq 0) {
        Write-PipelineMessage "No workbook subfolders found — skipping." -Level Info
        return $counters
    }

    Write-PipelineMessage "Found $($workbookDirs.Count) workbook(s) to process." -Level Info

    foreach ($dir in $workbookDirs) {
        try {
            $workbookPath = Join-Path $dir.FullName "workbook.json"
            $metadataPath = Join-Path $dir.FullName "metadata.json"

            if (-not (Test-ShouldDeployFile -FilePath $workbookPath)) {
                Write-PipelineMessage "Unchanged: $($dir.Name) — skipping (smart deployment)" -Level Info
                $counters.Skipped++
                continue
            }

            if (-not (Test-Path $workbookPath)) {
                Write-PipelineMessage "Skipping '$($dir.Name)': workbook.json not found." -Level Warning
                $counters.Skipped++
                continue
            }

            # Check dependency graph
            $depCheck = Test-ContentDependencies -ContentPath $workbookPath
            if (-not $depCheck.Passed) {
                Write-PipelineMessage "Skipping '$($dir.Name)': missing dependencies — $($depCheck.Missing -join ', ')" -Level Warning
                $counters.Skipped++
                continue
            }

            # Read the gallery template JSON
            $workbookContent = Get-Content -Path $workbookPath -Raw

            # Determine display name and workbook ID from metadata or folder name
            $displayName = $dir.Name -replace '([a-z])([A-Z])', '$1 $2'
            $workbookId = $null

            if (Test-Path $metadataPath) {
                $metadata = Get-Content -Path $metadataPath -Raw | ConvertFrom-Json
                if ($metadata.PSObject.Properties['displayName'] -and $metadata.displayName) {
                    $displayName = $metadata.displayName
                }
                if ($metadata.PSObject.Properties['workbookId'] -and $metadata.workbookId) {
                    $workbookId = $metadata.workbookId
                }
                if ($metadata.PSObject.Properties['category'] -and $metadata.category) {
                    $category = $metadata.category
                }
            }

            # Generate a deterministic GUID from workspace + folder name if not provided
            if (-not $workbookId) {
                $hashInput = "$($script:WorkspaceResourceId)-$($dir.Name)"
                $hashBytes = [System.Text.Encoding]::UTF8.GetBytes($hashInput)
                $sha256 = [System.Security.Cryptography.SHA256]::Create()
                $hashResult = $sha256.ComputeHash($hashBytes)
                [byte[]]$guidBytes = $hashResult[0..15]
                $workbookId = ([guid]::new($guidBytes)).ToString()
            }

            Write-PipelineMessage "Processing workbook: $displayName (ID: $workbookId)" -Level Info

            # Serialise the workbook content as a JSON string for the serializedData property
            $serializedData = $workbookContent

            $body = @{
                location   = $Region
                kind       = "shared"
                properties = @{
                    displayName    = $displayName
                    serializedData = $serializedData
                    version        = "1.0"
                    category       = "sentinel"
                    sourceId       = $script:WorkspaceResourceId
                }
            } | ConvertTo-Json -Depth 10

            $uri = "$($script:ServerUrl)/subscriptions/$($script:SubscriptionId)/resourceGroups/$ResourceGroup/providers/Microsoft.Insights/workbooks/$($workbookId)?api-version=$($script:WorkbookApiVersion)"

            if ($WhatIf) {
                Write-PipelineMessage "[WhatIf] Would deploy workbook: $displayName" -Level Info
                $counters.Deployed++
            }
            else {
                Invoke-SentinelApi -Uri $uri -Method Put -Headers $script:AuthHeader -Body $body | Out-Null
                Write-PipelineMessage "Deployed: $displayName" -Level Success
                $counters.Deployed++
                Set-DeploymentItemState -FilePath $workbookPath -Status "success"
            }
        }
        catch {
            Write-PipelineMessage "Failed to deploy workbook '$($dir.Name)': $($_.Exception.Message)" -Level Error
            $counters.Failed++
            Set-DeploymentItemState -FilePath $workbookPath -Status "failed"
        }
    }

    return $counters
}

# ---------------------------------------------------------------------------
# Deploy Custom Hunting Queries (YAML → Saved Searches)
# ---------------------------------------------------------------------------
function Deploy-CustomHuntingQueries {
    [CmdletBinding()]
    param()

    $counters = @{ Deployed = 0; Skipped = 0; Failed = 0 }
    $huntingPath = Join-Path $BasePath "HuntingQueries"

    Write-PipelineMessage "Deploying custom hunting queries..." -Level Section

    if (-not (Test-Path $huntingPath)) {
        Write-PipelineMessage "HuntingQueries folder not found at '$huntingPath' — skipping." -Level Warning
        return $counters
    }

    # Ensure powershell-yaml is available
    if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
        Write-PipelineMessage "Installing powershell-yaml module..." -Level Info
        Install-Module -Name powershell-yaml -Force -Scope CurrentUser
    }
    Import-Module powershell-yaml -ErrorAction Stop

    $yamlFiles = @(Get-ChildItem -Path $huntingPath -Include "*.yaml", "*.yml" -Recurse -File)
    if ($yamlFiles.Count -eq 0) {
        Write-PipelineMessage "No YAML files found in '$huntingPath' — skipping." -Level Info
        return $counters
    }

    $yamlFiles = @(Get-PrioritizedFiles -Files $yamlFiles)
    Write-PipelineMessage "Found $($yamlFiles.Count) hunting query file(s) to process." -Level Info

    foreach ($file in $yamlFiles) {
        if (-not (Test-ShouldDeployFile -FilePath $file.FullName)) {
            Write-PipelineMessage "Unchanged: $($file.Name) — skipping (smart deployment)" -Level Info
            $counters.Skipped++
            continue
        }
        try {
            $yamlContent = Get-Content -Path $file.FullName -Raw
            $hq = ConvertFrom-Yaml -Yaml $yamlContent

            # Validate required fields
            $requiredFields = @('id', 'name', 'query')
            $missingFields = @($requiredFields | Where-Object { -not $hq.ContainsKey($_) -or [string]::IsNullOrWhiteSpace($hq[$_]) })
            if ($missingFields.Count -gt 0) {
                Write-PipelineMessage "Skipping '$($file.Name)': missing required fields: $($missingFields -join ', ')" -Level Warning
                $counters.Skipped++
                continue
            }

            $queryId = $hq['id']
            $queryName = $hq['name']

            # Check dependency graph — skip if prerequisites are not met
            $depCheck = Test-ContentDependencies -ContentPath $file.FullName
            if (-not $depCheck.Passed) {
                Write-PipelineMessage "Skipping '$($file.Name)': missing dependencies — $($depCheck.Missing -join ', ')" -Level Warning
                $counters.Skipped++
                continue
            }

            Write-PipelineMessage "Processing: $queryName [$($file.Name)]" -Level Info

            # Build tags array for the saved search
            $tags = @()

            if ($hq.ContainsKey('description') -and -not [string]::IsNullOrWhiteSpace($hq['description'])) {
                $tags += @{ name = "description"; value = $hq['description'] }
            }
            if ($hq.ContainsKey('tactics') -and $hq['tactics']) {
                $tacticsValue = ([array]$hq['tactics']) -join ','
                $tags += @{ name = "tactics"; value = $tacticsValue }
            }
            if ($hq.ContainsKey('techniques') -and $hq['techniques']) {
                $allTechs = [array]$hq['techniques']
                # Parent techniques (T####)
                $techniquesValue = ($allTechs | ForEach-Object { ($_ -split '\.')[0] } | Select-Object -Unique) -join ','
                $tags += @{ name = "techniques"; value = $techniquesValue }
                # Sub-techniques (T####.###) as separate tag
                $subTechsValue = ($allTechs | Where-Object { $_ -match '\.' } | Select-Object -Unique) -join ','
                if ($subTechsValue) {
                    $tags += @{ name = "subTechniques"; value = $subTechsValue }
                }
            }
            if ($hq.ContainsKey('tags') -and $hq['tags']) {
                foreach ($tag in $hq['tags']) {
                    $tags += @{ name = $tag['name']; value = $tag['value'] }
                }
            }

            $properties = @{
                category    = "Hunting Queries"
                displayName = $queryName
                query       = $hq['query']
            }

            if ($tags.Count -gt 0) {
                $properties.tags = $tags
            }

            $body = @{
                properties = $properties
            } | ConvertTo-Json -Depth 10

            $uri = "$($script:ServerUrl)/subscriptions/$($script:SubscriptionId)/resourceGroups/$ResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$Workspace/savedSearches/$($queryId)?api-version=$($script:SavedSearchApiVersion)"

            if ($WhatIf) {
                Write-PipelineMessage "[WhatIf] Would deploy hunting query: $queryName" -Level Info
                $counters.Deployed++
            }
            else {
                Invoke-SentinelApi -Uri $uri -Method Put -Headers $script:AuthHeader -Body $body | Out-Null
                Write-PipelineMessage "Deployed: $queryName" -Level Success
                $counters.Deployed++
                Set-DeploymentItemState -FilePath $file.FullName -Status "success"
            }
        }
        catch {
            Write-PipelineMessage "Failed to deploy '$($file.Name)': $($_.Exception.Message)" -Level Error
            $counters.Failed++
            Set-DeploymentItemState -FilePath $file.FullName -Status "failed"
        }
    }

    return $counters
}

# ---------------------------------------------------------------------------
# Deploy Custom Automation Rules (JSON)
# ---------------------------------------------------------------------------
function Deploy-CustomAutomationRules {
    [CmdletBinding()]
    param()

    $counters = @{ Deployed = 0; Skipped = 0; Failed = 0 }
    $automationPath = Join-Path $BasePath "AutomationRules"

    Write-PipelineMessage "Deploying custom automation rules..." -Level Section

    if (-not (Test-Path $automationPath)) {
        Write-PipelineMessage "AutomationRules folder not found at '$automationPath' — skipping." -Level Warning
        return $counters
    }

    $jsonFiles = @(Get-ChildItem -Path $automationPath -Include "*.json" -Recurse -File | Where-Object { $_.Name -ne "README.md" })
    if ($jsonFiles.Count -eq 0) {
        Write-PipelineMessage "No JSON files found in '$automationPath' — skipping." -Level Info
        return $counters
    }

    Write-PipelineMessage "Found $($jsonFiles.Count) automation rule file(s) to process." -Level Info

    foreach ($file in $jsonFiles) {
        if (-not (Test-ShouldDeployFile -FilePath $file.FullName)) {
            Write-PipelineMessage "Unchanged: $($file.Name) — skipping (smart deployment)" -Level Info
            $counters.Skipped++
            continue
        }
        try {
            $jsonContent = Get-Content -Path $file.FullName -Raw
            $rule = $jsonContent | ConvertFrom-Json

            # Validate required fields
            if (-not $rule.automationRuleId -or -not $rule.displayName -or $null -eq $rule.order -or -not $rule.triggeringLogic -or -not $rule.actions) {
                Write-PipelineMessage "Skipping '$($file.Name)': missing required fields (automationRuleId, displayName, order, triggeringLogic, actions)." -Level Warning
                $counters.Skipped++
                continue
            }

            $ruleId = $rule.automationRuleId
            $ruleName = $rule.displayName

            # Check dependency graph
            $depCheck = Test-ContentDependencies -ContentPath $file.FullName
            if (-not $depCheck.Passed) {
                Write-PipelineMessage "Skipping '$($file.Name)': missing dependencies — $($depCheck.Missing -join ', ')" -Level Warning
                $counters.Skipped++
                continue
            }

            Write-PipelineMessage "Processing: $ruleName (order: $($rule.order)) [$($file.Name)]" -Level Info

            # Build the API body — the JSON file structure maps directly to the properties object
            $body = @{
                properties = @{
                    displayName     = $ruleName
                    order           = [int]$rule.order
                    triggeringLogic = $rule.triggeringLogic
                    actions         = @($rule.actions)
                }
            } | ConvertTo-Json -Depth 20

            $uri = "$($script:BaseUri)/providers/Microsoft.SecurityInsights/automationRules/$($ruleId)?api-version=$($script:SentinelApiVersion)"

            if ($WhatIf) {
                Write-PipelineMessage "[WhatIf] Would deploy automation rule: $ruleName" -Level Info
                $counters.Deployed++
            }
            else {
                Invoke-SentinelApi -Uri $uri -Method Put -Headers $script:AuthHeader -Body $body | Out-Null
                Write-PipelineMessage "Deployed: $ruleName" -Level Success
                $counters.Deployed++
                Set-DeploymentItemState -FilePath $file.FullName -Status "success"
            }
        }
        catch {
            Write-PipelineMessage "Failed to deploy '$($file.Name)': $($_.Exception.Message)" -Level Error
            $counters.Failed++
            Set-DeploymentItemState -FilePath $file.FullName -Status "failed"
        }
    }

    return $counters
}

# ---------------------------------------------------------------------------
# Deploy Custom Summary Rules (JSON → Log Analytics summarylogs)
# ---------------------------------------------------------------------------
function Deploy-CustomSummaryRules {
    [CmdletBinding()]
    param()

    $counters = @{ Deployed = 0; Skipped = 0; Failed = 0 }
    $summaryPath = Join-Path $BasePath "SummaryRules"

    Write-PipelineMessage "Deploying custom summary rules..." -Level Section

    if (-not (Test-Path $summaryPath)) {
        Write-PipelineMessage "SummaryRules folder not found at '$summaryPath' — skipping." -Level Warning
        return $counters
    }

    $jsonFiles = @(Get-ChildItem -Path $summaryPath -Include "*.json" -Recurse -File | Where-Object { $_.Name -ne "README.md" })
    if ($jsonFiles.Count -eq 0) {
        Write-PipelineMessage "No JSON files found in '$summaryPath' — skipping." -Level Info
        return $counters
    }

    Write-PipelineMessage "Found $($jsonFiles.Count) summary rule file(s) to process." -Level Info

    $validBinSizes = @(20, 30, 60, 120, 180, 360, 720, 1440)

    foreach ($file in $jsonFiles) {
        if (-not (Test-ShouldDeployFile -FilePath $file.FullName)) {
            Write-PipelineMessage "Unchanged: $($file.Name) — skipping (smart deployment)" -Level Info
            $counters.Skipped++
            continue
        }
        try {
            $jsonContent = Get-Content -Path $file.FullName -Raw
            $rule = $jsonContent | ConvertFrom-Json

            # Validate required fields
            if (-not $rule.name -or -not $rule.query -or $null -eq $rule.binSize -or -not $rule.destinationTable) {
                Write-PipelineMessage "Skipping '$($file.Name)': missing required fields (name, query, binSize, destinationTable)." -Level Warning
                $counters.Skipped++
                continue
            }

            # Validate binSize
            if ($validBinSizes -notcontains [int]$rule.binSize) {
                Write-PipelineMessage "Skipping '$($file.Name)': invalid binSize '$($rule.binSize)'. Allowed values: $($validBinSizes -join ', ')." -Level Warning
                $counters.Skipped++
                continue
            }

            # Validate destination table suffix
            if (-not $rule.destinationTable.EndsWith("_CL")) {
                Write-PipelineMessage "Skipping '$($file.Name)': destinationTable must end with '_CL' suffix." -Level Warning
                $counters.Skipped++
                continue
            }

            $ruleName = $rule.name
            $displayName = if ($rule.displayName) { $rule.displayName } else { $ruleName }

            # Check dependency graph
            $depCheck = Test-ContentDependencies -ContentPath $file.FullName
            if (-not $depCheck.Passed) {
                Write-PipelineMessage "Skipping '$($file.Name)': missing dependencies — $($depCheck.Missing -join ', ')" -Level Warning
                $counters.Skipped++
                continue
            }

            Write-PipelineMessage "Processing: $displayName (bin: $($rule.binSize)min → $($rule.destinationTable)) [$($file.Name)]" -Level Info

            # Build the ruleDefinition object
            $ruleDefinition = @{
                query            = $rule.query
                binSize          = [int]$rule.binSize
                destinationTable = $rule.destinationTable
            }

            if ($rule.PSObject.Properties['binDelay'] -and $null -ne $rule.binDelay) {
                $ruleDefinition.binDelay = [int]$rule.binDelay
            }
            if ($rule.PSObject.Properties['binStartTime'] -and $rule.binStartTime) {
                $ruleDefinition.binStartTime = $rule.binStartTime
            }

            $properties = @{
                ruleType       = "User"
                ruleDefinition = $ruleDefinition
            }

            if ($rule.PSObject.Properties['description'] -and $rule.description) {
                $properties.description = $rule.description
            }
            if ($rule.PSObject.Properties['displayName'] -and $rule.displayName) {
                $properties.displayName = $rule.displayName
            }

            $body = @{
                properties = $properties
            } | ConvertTo-Json -Depth 10

            # Summary rules use the Log Analytics provider, not SecurityInsights
            $uri = "$($script:ServerUrl)/subscriptions/$($script:SubscriptionId)/resourceGroups/$ResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$Workspace/summarylogs/$($ruleName)?api-version=$($script:SummaryRuleApiVersion)"

            if ($WhatIf) {
                Write-PipelineMessage "[WhatIf] Would deploy summary rule: $displayName (bin: $($rule.binSize)min → $($rule.destinationTable))" -Level Info
                $counters.Deployed++
            }
            else {
                Invoke-SentinelApi -Uri $uri -Method Put -Headers $script:AuthHeader -Body $body | Out-Null
                Write-PipelineMessage "Deployed: $displayName" -Level Success
                $counters.Deployed++
                Set-DeploymentItemState -FilePath $file.FullName -Status "success"
            }
        }
        catch {
            Write-PipelineMessage "Failed to deploy '$($file.Name)': $($_.Exception.Message)" -Level Error
            $counters.Failed++
            Set-DeploymentItemState -FilePath $file.FullName -Status "failed"
        }
    }

    return $counters
}

# ---------------------------------------------------------------------------
# Summary Reporter
# ---------------------------------------------------------------------------
function Write-DeploymentSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Results
        ,
        [Parameter(Mandatory = $true)]
        [timespan]$Duration
    )

    Write-PipelineMessage "Custom Content Deployment Summary" -Level Section
    Write-PipelineMessage ("=" * 60) -Level Info

    $totalDeployed = 0
    $totalSkipped = 0
    $totalFailed = 0

    foreach ($contentType in @("Parsers", "AnalyticalRules", "Watchlists", "Playbooks", "Workbooks", "HuntingQueries", "AutomationRules", "SummaryRules")) {
        $result = $Results[$contentType]
        if (-not $result) {
            Write-PipelineMessage "  $($contentType.PadRight(15)) Deployed: 0  Skipped: 0  Failed: 0  [SKIPPED]" -Level Info
            continue
        }
        $totalDeployed += $result.Deployed
        $totalSkipped += $result.Skipped
        $totalFailed += $result.Failed

        $status = if ($result.Failed -gt 0) { "PARTIAL" } elseif ($result.Deployed -gt 0) { "OK" } else { "SKIPPED" }
        Write-PipelineMessage "  $($contentType.PadRight(15)) Deployed: $($result.Deployed)  Skipped: $($result.Skipped)  Failed: $($result.Failed)  [$status]" -Level Info
    }

    Write-PipelineMessage ("=" * 60) -Level Info
    Write-PipelineMessage "  $("TOTAL".PadRight(15)) Deployed: $totalDeployed  Skipped: $totalSkipped  Failed: $totalFailed" -Level Info
    Write-PipelineMessage "  Duration: $($Duration.ToString('hh\:mm\:ss'))" -Level Info

    if ($totalFailed -gt 0) {
        Write-PipelineMessage "$totalFailed item(s) failed to deploy. Review errors above." -Level Error
    }
    elseif ($totalDeployed -gt 0) {
        Write-PipelineMessage "All items deployed successfully." -Level Success
    }

    return $totalFailed
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
function Main {
    $scriptStartTime = Get-Date

    Write-PipelineMessage ("=" * 60) -Level Info
    Write-PipelineMessage "  Sentinel-As-Code: Custom Content Deployment" -Level Section
    Write-PipelineMessage ("=" * 60) -Level Info

    if ($WhatIf) {
        Write-PipelineMessage "DRY RUN MODE — no changes will be made." -Level Warning
    }

    # ── Step 1/12: Configuration ──────────────────────────────────────────
    Write-PipelineMessage "" -Level Info
    Write-PipelineMessage "Step 1/12: Configuration" -Level Section
    Write-PipelineMessage ("─" * 60) -Level Info
    Write-PipelineMessage "  Base Path:     $BasePath" -Level Info
    Write-PipelineMessage "  Smart Deploy:  $(if ($SmartDeployment) { 'ENABLED' } else { 'DISABLED (full deploy)' })" -Level Info
    Write-PipelineMessage "  Parsers:       $(if ($SkipParsers) { 'SKIP' } else { 'ENABLED' })" -Level Info
    Write-PipelineMessage "  Detections:    $(if ($SkipDetections) { 'SKIP' } else { 'ENABLED' })" -Level Info
    Write-PipelineMessage "  Watchlists:    $(if ($SkipWatchlists) { 'SKIP' } else { 'ENABLED' })" -Level Info
    Write-PipelineMessage "  Playbooks:     $(if ($SkipPlaybooks) { 'SKIP' } else { 'ENABLED' })" -Level Info
    Write-PipelineMessage "  Workbooks:     $(if ($SkipWorkbooks) { 'SKIP' } else { 'ENABLED' })" -Level Info
    Write-PipelineMessage "  Hunting:       $(if ($SkipHuntingQueries) { 'SKIP' } else { 'ENABLED' })" -Level Info
    Write-PipelineMessage "  Automation:    $(if ($SkipAutomationRules) { 'SKIP' } else { 'ENABLED' })" -Level Info
    Write-PipelineMessage "  Summary:       $(if ($SkipSummaryRules) { 'SKIP' } else { 'ENABLED' })" -Level Info

    # ── Step 2/12: Authentication ─────────────────────────────────────────
    Write-PipelineMessage "" -Level Info
    Write-PipelineMessage "Step 2/12: Authentication" -Level Section
    Write-PipelineMessage ("─" * 60) -Level Info
    Connect-AzureEnvironment

    # ── Step 3/12: Smart Deployment ───────────────────────────────────────
    Write-PipelineMessage "" -Level Info
    Write-PipelineMessage "Step 3/12: Smart Deployment" -Level Section
    Write-PipelineMessage ("─" * 60) -Level Info
    Initialize-SmartDeployment
    Initialize-DeploymentState

    # ── Step 4/12: Dependency Graph & Pre-Flight ──────────────────────────
    Write-PipelineMessage "" -Level Info
    Write-PipelineMessage "Step 4/12: Dependency Graph & Pre-Flight Checks" -Level Section
    Write-PipelineMessage ("─" * 60) -Level Info
    Initialize-DependencyGraph
    Invoke-PreFlightChecks

    $results = @{
        Parsers         = @{ Deployed = 0; Skipped = 0; Failed = 0 }
        AnalyticalRules = @{ Deployed = 0; Skipped = 0; Failed = 0 }
        Watchlists      = @{ Deployed = 0; Skipped = 0; Failed = 0 }
        Playbooks       = @{ Deployed = 0; Skipped = 0; Failed = 0 }
        Workbooks       = @{ Deployed = 0; Skipped = 0; Failed = 0 }
        HuntingQueries  = @{ Deployed = 0; Skipped = 0; Failed = 0 }
        AutomationRules = @{ Deployed = 0; Skipped = 0; Failed = 0 }
        SummaryRules    = @{ Deployed = 0; Skipped = 0; Failed = 0 }
    }

    # ── Step 5/12: Deploy Parsers ─────────────────────────────────────────
    Write-PipelineMessage "" -Level Info
    Write-PipelineMessage "Step 5/12: KQL Parsers & Functions" -Level Section
    Write-PipelineMessage ("─" * 60) -Level Info
    if (-not $SkipParsers) {
        $results.Parsers = Deploy-CustomParsers
    }
    else {
        Write-PipelineMessage "  Skipped (SkipParsers flag set)." -Level Info
    }
    Save-DeploymentState

    # ── Step 6/12: Deploy Watchlists ──────────────────────────────────────
    Write-PipelineMessage "" -Level Info
    Write-PipelineMessage "Step 6/12: Watchlists" -Level Section
    Write-PipelineMessage ("─" * 60) -Level Info
    if (-not $SkipWatchlists) {
        $results.Watchlists = Deploy-CustomWatchlists

        # Allow Sentinel to index watchlist schemas before deploying rules that reference them
        if ($results.Watchlists.Deployed -gt 0 -and -not $WhatIf) {
            Write-PipelineMessage "Waiting 30s for watchlist schema propagation..." -Level Info
            Start-Sleep -Seconds 30
        }
    }
    else {
        Write-PipelineMessage "  Skipped (SkipWatchlists flag set)." -Level Info
    }
    Save-DeploymentState

    # ── Step 7/12: Deploy Detections ──────────────────────────────────────
    Write-PipelineMessage "" -Level Info
    Write-PipelineMessage "Step 7/12: Analytics Rules (Detections)" -Level Section
    Write-PipelineMessage ("─" * 60) -Level Info
    if (-not $SkipDetections) {
        $results.AnalyticalRules = Deploy-CustomDetections
    }
    else {
        Write-PipelineMessage "  Skipped (SkipDetections flag set)." -Level Info
    }
    Save-DeploymentState

    # ── Step 8/12: Deploy Hunting Queries ─────────────────────────────────
    Write-PipelineMessage "" -Level Info
    Write-PipelineMessage "Step 8/12: Hunting Queries" -Level Section
    Write-PipelineMessage ("─" * 60) -Level Info
    if (-not $SkipHuntingQueries) {
        $results.HuntingQueries = Deploy-CustomHuntingQueries
    }
    else {
        Write-PipelineMessage "  Skipped (SkipHuntingQueries flag set)." -Level Info
    }
    Save-DeploymentState

    # ── Step 9/12: Deploy Playbooks ───────────────────────────────────────
    Write-PipelineMessage "" -Level Info
    Write-PipelineMessage "Step 9/12: Playbooks (Logic Apps)" -Level Section
    Write-PipelineMessage ("─" * 60) -Level Info
    if (-not $SkipPlaybooks) {
        $results.Playbooks = Deploy-CustomPlaybooks
    }
    else {
        Write-PipelineMessage "  Skipped (SkipPlaybooks flag set)." -Level Info
    }
    Save-DeploymentState

    # ── Step 10/12: Deploy Workbooks ──────────────────────────────────────
    Write-PipelineMessage "" -Level Info
    Write-PipelineMessage "Step 10/12: Workbooks" -Level Section
    Write-PipelineMessage ("─" * 60) -Level Info
    if (-not $SkipWorkbooks) {
        $results.Workbooks = Deploy-CustomWorkbooks
    }
    else {
        Write-PipelineMessage "  Skipped (SkipWorkbooks flag set)." -Level Info
    }
    Save-DeploymentState

    # ── Step 11/12: Deploy Automation Rules ────────────────────────────────
    Write-PipelineMessage "" -Level Info
    Write-PipelineMessage "Step 11/12: Automation Rules" -Level Section
    Write-PipelineMessage ("─" * 60) -Level Info
    if (-not $SkipAutomationRules) {
        $results.AutomationRules = Deploy-CustomAutomationRules
    }
    else {
        Write-PipelineMessage "  Skipped (SkipAutomationRules flag set)." -Level Info
    }
    Save-DeploymentState

    # ── Step 12/12: Deploy Summary Rules ──────────────────────────────────
    Write-PipelineMessage "" -Level Info
    Write-PipelineMessage "Step 12/12: Summary Rules" -Level Section
    Write-PipelineMessage ("─" * 60) -Level Info
    if (-not $SkipSummaryRules) {
        $results.SummaryRules = Deploy-CustomSummaryRules
    }
    else {
        Write-PipelineMessage "  Skipped (SkipSummaryRules flag set)." -Level Info
    }
    Save-DeploymentState

    # ── Summary ───────────────────────────────────────────────────────────
    Write-PipelineMessage "" -Level Info
    $duration = (Get-Date) - $scriptStartTime
    $totalFailed = Write-DeploymentSummary -Results $results -Duration $duration

    if ($totalFailed -gt 0) {
        exit 1
    }
}

Main

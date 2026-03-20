<#
.SYNOPSIS
    Deploys custom Microsoft Sentinel content from the repository to a workspace.

.DESCRIPTION
    This script automates the deployment of custom Sentinel content stored in the
    repository: analytics rules (detections), watchlists, playbooks, workbooks,
    hunting queries, and automation rules.

    It is designed to run in Azure DevOps (ADO) pipelines using a Service Principal
    or Managed Identity for authentication. The script uses the latest GA API version
    (2025-09-01) for Sentinel operations.

    Key capabilities:
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

.PARAMETER Workspace
    The name of the Log Analytics workspace with Microsoft Sentinel enabled.

.PARAMETER Region
    The Azure region (location) where the workspace is deployed (e.g. 'uksouth').

.PARAMETER BasePath
    The root path of the repository containing content folders (Detections/,
    Watchlists/, Playbooks/, Workbooks/). Defaults to the parent of the Scripts folder.

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
    API Version:    2025-09-01 (GA)
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
    [switch]$WhatIf
)

#Requires -Modules Az.Accounts

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$InformationPreference = "Continue"

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
$script:SentinelApiVersion  = "2024-09-01"
$script:SentinelPreviewApiVersion = "2024-01-01-preview"
$script:WorkbookApiVersion  = "2022-04-01"
$script:SavedSearchApiVersion = "2020-08-01"
$script:SummaryRuleApiVersion = "2025-07-01"

# ---------------------------------------------------------------------------
# Resolve BasePath
# ---------------------------------------------------------------------------
if (-not $BasePath) {
    $BasePath = Split-Path $PSScriptRoot -Parent
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
    Update-AzConfig -DisplayBreakingChangeWarning $false -ErrorAction SilentlyContinue | Out-Null

    $context = Get-AzContext

    if (-not $context) {
        Write-PipelineMessage "No Azure context found. Attempting login..." -Level Info
        if ($IsGov) {
            Connect-AzAccount -Environment AzureUSGovernment -ErrorAction Stop | Out-Null
        }
        else {
            Connect-AzAccount -ErrorAction Stop | Out-Null
        }
        $context = Get-AzContext
    }

    if (-not $context) {
        throw "Failed to establish Azure context. Ensure you are authenticated."
    }

    if ($script:SubscriptionId) {
        Set-AzContext -SubscriptionId $script:SubscriptionId -ErrorAction Stop | Out-Null
        $context = Get-AzContext
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

    $resourceEndpoint = $script:ServerUrl
    try {
        $tokenResponse = Get-AzAccessToken -ResourceUrl $resourceEndpoint -ErrorAction Stop

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
    if ($IsGov) {
        Write-PipelineMessage "Azure Government cloud mode enabled." -Level Info
    }
}

# ---------------------------------------------------------------------------
# Deploy Custom Detections (Analytics Rules from YAML)
# ---------------------------------------------------------------------------
function Deploy-CustomDetections {
    [CmdletBinding()]
    param()

    $counters = @{ Deployed = 0; Skipped = 0; Failed = 0 }
    $detectionsPath = Join-Path $BasePath "Detections"

    Write-PipelineMessage "Deploying custom analytics rules..." -Level Section

    if (-not (Test-Path $detectionsPath)) {
        Write-PipelineMessage "Detections folder not found at '$detectionsPath' — skipping." -Level Warning
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

    Write-PipelineMessage "Found $($yamlFiles.Count) detection file(s) to process." -Level Info

    foreach ($file in $yamlFiles) {
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

            Write-PipelineMessage "Processing: $ruleName ($ruleKind) [$($file.Name)]" -Level Info

            # Build the API properties
            $ruleDescription = if ($rule.ContainsKey('description')) { $rule['description'] } else { "" }
            $ruleEnabled     = if ($rule.ContainsKey('enabled')) { [bool]$rule['enabled'] } else { $true }

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
                $properties.techniques = [array]$rule[$techKey]
            }
            if ($rule.ContainsKey('entityMappings')) {
                $properties.entityMappings = [array]$rule['entityMappings']
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

            # NRT rules require preview API version
            $apiVer = if ($ruleKind -eq "NRT") { $script:SentinelPreviewApiVersion } else { $script:SentinelApiVersion }
            $uri = "$($script:BaseUri)/providers/Microsoft.SecurityInsights/alertRules/$($ruleId)?api-version=$apiVer"

            if ($WhatIf) {
                Write-PipelineMessage "[WhatIf] Would deploy detection: $ruleName ($ruleKind, $($rule['severity']))" -Level Info
                $counters.Deployed++
            }
            else {
                Invoke-SentinelApi -Uri $uri -Method Put -Headers $script:AuthHeader -Body $body | Out-Null
                Write-PipelineMessage "Deployed: $ruleName" -Level Success
                $counters.Deployed++
            }
        }
        catch {
            Write-PipelineMessage "Failed to deploy '$($file.Name)': $($_.Exception.Message)" -Level Error
            $counters.Failed++
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
            }
        }
        catch {
            Write-PipelineMessage "Failed to deploy watchlist '$($dir.Name)': $($_.Exception.Message)" -Level Error
            $counters.Failed++
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

    $playbookDirs = @(Get-ChildItem -Path $playbooksPath -Directory)
    if ($playbookDirs.Count -eq 0) {
        Write-PipelineMessage "No playbook subfolders found — skipping." -Level Info
        return $counters
    }

    Write-PipelineMessage "Found $($playbookDirs.Count) playbook(s) to process." -Level Info

    foreach ($dir in $playbookDirs) {
        try {
            $templatePath = Join-Path $dir.FullName "azuredeploy.json"
            $parametersPath = Join-Path $dir.FullName "azuredeploy.parameters.json"

            if (-not (Test-Path $templatePath)) {
                Write-PipelineMessage "Skipping '$($dir.Name)': azuredeploy.json not found." -Level Warning
                $counters.Skipped++
                continue
            }

            Write-PipelineMessage "Processing playbook: $($dir.Name)" -Level Info

            $deploymentName = "Playbook-$($dir.Name)-$(Get-Date -Format 'yyyyMMddHHmmss')"

            $deployParams = @{
                ResourceGroupName = $ResourceGroup
                TemplateFile      = $templatePath
                Name              = $deploymentName
            }

            if (Test-Path $parametersPath) {
                $deployParams.TemplateParameterFile = $parametersPath
                Write-PipelineMessage "  Using parameters file: azuredeploy.parameters.json" -Level Debug
            }

            if ($WhatIf) {
                Write-PipelineMessage "[WhatIf] Would deploy playbook: $($dir.Name)" -Level Info
                try {
                    Test-AzResourceGroupDeployment @deployParams -ErrorAction Stop | Out-Null
                    Write-PipelineMessage "[WhatIf] Template validation passed for '$($dir.Name)'." -Level Success
                }
                catch {
                    Write-PipelineMessage "[WhatIf] Template validation failed for '$($dir.Name)': $($_.Exception.Message)" -Level Warning
                }
                $counters.Deployed++
            }
            else {
                New-AzResourceGroupDeployment @deployParams -ErrorAction Stop | Out-Null
                Write-PipelineMessage "Deployed: $($dir.Name)" -Level Success
                $counters.Deployed++
            }
        }
        catch {
            Write-PipelineMessage "Failed to deploy playbook '$($dir.Name)': $($_.Exception.Message)" -Level Error
            $counters.Failed++
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

            if (-not (Test-Path $workbookPath)) {
                Write-PipelineMessage "Skipping '$($dir.Name)': workbook.json not found." -Level Warning
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
            }
        }
        catch {
            Write-PipelineMessage "Failed to deploy workbook '$($dir.Name)': $($_.Exception.Message)" -Level Error
            $counters.Failed++
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

    Write-PipelineMessage "Found $($yamlFiles.Count) hunting query file(s) to process." -Level Info

    foreach ($file in $yamlFiles) {
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
                $techniquesValue = ([array]$hq['techniques']) -join ','
                $tags += @{ name = "techniques"; value = $techniquesValue }
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
            }
        }
        catch {
            Write-PipelineMessage "Failed to deploy '$($file.Name)': $($_.Exception.Message)" -Level Error
            $counters.Failed++
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
            }
        }
        catch {
            Write-PipelineMessage "Failed to deploy '$($file.Name)': $($_.Exception.Message)" -Level Error
            $counters.Failed++
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
            }
        }
        catch {
            Write-PipelineMessage "Failed to deploy '$($file.Name)': $($_.Exception.Message)" -Level Error
            $counters.Failed++
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

    foreach ($contentType in @("Detections", "Watchlists", "Playbooks", "Workbooks", "HuntingQueries", "AutomationRules", "SummaryRules")) {
        $result = $Results[$contentType]
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

    Write-PipelineMessage "Configuration:" -Level Info
    Write-PipelineMessage "  Base Path:     $BasePath" -Level Info
    Write-PipelineMessage "  Detections:    $(if ($SkipDetections) { 'SKIP' } else { 'ENABLED' })" -Level Info
    Write-PipelineMessage "  Watchlists:    $(if ($SkipWatchlists) { 'SKIP' } else { 'ENABLED' })" -Level Info
    Write-PipelineMessage "  Playbooks:     $(if ($SkipPlaybooks) { 'SKIP' } else { 'ENABLED' })" -Level Info
    Write-PipelineMessage "  Workbooks:     $(if ($SkipWorkbooks) { 'SKIP' } else { 'ENABLED' })" -Level Info
    Write-PipelineMessage "  Hunting:       $(if ($SkipHuntingQueries) { 'SKIP' } else { 'ENABLED' })" -Level Info
    Write-PipelineMessage "  Automation:    $(if ($SkipAutomationRules) { 'SKIP' } else { 'ENABLED' })" -Level Info
    Write-PipelineMessage "  Summary:       $(if ($SkipSummaryRules) { 'SKIP' } else { 'ENABLED' })" -Level Info

    Connect-AzureEnvironment

    $results = @{
        Detections      = @{ Deployed = 0; Skipped = 0; Failed = 0 }
        Watchlists      = @{ Deployed = 0; Skipped = 0; Failed = 0 }
        Playbooks       = @{ Deployed = 0; Skipped = 0; Failed = 0 }
        Workbooks       = @{ Deployed = 0; Skipped = 0; Failed = 0 }
        HuntingQueries  = @{ Deployed = 0; Skipped = 0; Failed = 0 }
        AutomationRules = @{ Deployed = 0; Skipped = 0; Failed = 0 }
        SummaryRules    = @{ Deployed = 0; Skipped = 0; Failed = 0 }
    }

    if (-not $SkipDetections) {
        $results.Detections = Deploy-CustomDetections
    }
    else {
        Write-PipelineMessage "Skipping detections (SkipDetections flag set)." -Level Info
    }

    if (-not $SkipWatchlists) {
        $results.Watchlists = Deploy-CustomWatchlists
    }
    else {
        Write-PipelineMessage "Skipping watchlists (SkipWatchlists flag set)." -Level Info
    }

    if (-not $SkipPlaybooks) {
        $results.Playbooks = Deploy-CustomPlaybooks
    }
    else {
        Write-PipelineMessage "Skipping playbooks (SkipPlaybooks flag set)." -Level Info
    }

    if (-not $SkipWorkbooks) {
        $results.Workbooks = Deploy-CustomWorkbooks
    }
    else {
        Write-PipelineMessage "Skipping workbooks (SkipWorkbooks flag set)." -Level Info
    }

    if (-not $SkipHuntingQueries) {
        $results.HuntingQueries = Deploy-CustomHuntingQueries
    }
    else {
        Write-PipelineMessage "Skipping hunting queries (SkipHuntingQueries flag set)." -Level Info
    }

    if (-not $SkipAutomationRules) {
        $results.AutomationRules = Deploy-CustomAutomationRules
    }
    else {
        Write-PipelineMessage "Skipping automation rules (SkipAutomationRules flag set)." -Level Info
    }

    if (-not $SkipSummaryRules) {
        $results.SummaryRules = Deploy-CustomSummaryRules
    }
    else {
        Write-PipelineMessage "Skipping summary rules (SkipSummaryRules flag set)." -Level Info
    }

    $duration = (Get-Date) - $scriptStartTime
    $totalFailed = Write-DeploymentSummary -Results $results -Duration $duration

    if ($totalFailed -gt 0) {
        exit 1
    }
}

Main

<#
.SYNOPSIS
    Deploys Microsoft Sentinel Content Hub solutions and their associated content to a workspace.

.DESCRIPTION
    This script automates the end-to-end deployment of Microsoft Sentinel Content Hub solutions
    and their packaged content (Analytics Rules, Workbooks, Automation Rules, Hunting Queries,
    Parsers, Playbooks) via the Azure REST API.

    It is designed to run in Azure DevOps (ADO) pipelines using a Service Principal or Managed
    Identity for authentication. The script uses the latest GA API version (2025-09-01) for all
    Microsoft Sentinel operations and the 2024-11-01 API version for ARM template deployments.

    Key capabilities:
    - Select solutions by name for targeted deployment
    - Detect solutions that require updates (semantic version comparison)
    - Deploy out-of-the-box (OoB) content: Analytics Rules, Workbooks, Automation Rules
    - Detect and skip locally modified (customised) Analytics Rules with pipeline warnings
    - Set newly deployed Analytics Rules to disabled by default
    - Granular control via switches for each content type
    - Proper metadata linking so content appears correctly in Content Hub

.PARAMETER SubscriptionId
    The Azure Subscription ID containing the Sentinel workspace. If not provided, the script
    will attempt to use the current Azure context.

.PARAMETER ResourceGroup
    The name of the Azure Resource Group containing the Sentinel workspace.

.PARAMETER Workspace
    The name of the Log Analytics workspace with Microsoft Sentinel enabled.

.PARAMETER Region
    The Azure region (location) where the workspace is deployed (e.g. 'uksouth', 'eastus').

.PARAMETER Solutions
    An array of Content Hub solution names to deploy (e.g. 'Microsoft Defender XDR', 'Azure Activity').

.PARAMETER SeveritiesToInclude
    An optional array of Analytics Rule severities to include. Defaults to High, Medium, Low, Informational.

.PARAMETER DisableRules
    When specified, deploys Analytics Rules in a disabled state. This is the recommended default
    for production pipelines to allow review before enabling.

.PARAMETER SkipSolutionDeployment
    When specified, skips deploying/updating solutions entirely and only processes content.

.PARAMETER SkipAnalyticsRules
    When specified, skips deploying Analytics Rules.

.PARAMETER SkipWorkbooks
    When specified, skips deploying Workbooks.

.PARAMETER SkipAutomationRules
    When specified, skips deploying Automation Rules.

.PARAMETER SkipHuntingQueries
    When specified, skips deploying Hunting Queries.

.PARAMETER ForceSolutionUpdate
    When specified, forces update of already installed solutions even if the version matches.

.PARAMETER ForceContentDeployment
    When specified, forces redeployment of all content even if versions match.

.PARAMETER ProtectCustomisedRules
    When specified (default), detects Analytics Rules that have been modified from their template
    and skips updating them. Emits ADO pipeline warnings for visibility.

.PARAMETER IsGov
    When specified, targets the Azure Government cloud environment.

.PARAMETER WhatIf
    When specified, performs a dry run showing what actions would be taken without making changes.

.NOTES
    Author:         noodlemctwoodle
    Version:        2.1.0
    Last Updated:   2026-04-28
    Repository:     Sentinel-As-Code
    API Version:    2025-09-01 (GA)
    Requires:       Az.Accounts PowerShell module
    Pipeline:       Azure DevOps (ADO) with Azure Service Connection

.EXAMPLE
    .\Deploy-SentinelContentHub.ps1 `
        -ResourceGroup "rg-sentinel-prod" `
        -Workspace "law-sentinel-prod" `
        -Region "uksouth" `
        -Solutions "Microsoft Defender XDR", "Azure Activity" `
        -DisableRules

    Deploys two solutions and their content with Analytics Rules set to disabled.

.EXAMPLE
    .\Deploy-SentinelContentHub.ps1 `
        -ResourceGroup "rg-sentinel-prod" `
        -Workspace "law-sentinel-prod" `
        -Region "uksouth" `
        -Solutions "Microsoft Defender XDR" `
        -SkipWorkbooks `
        -SkipAutomationRules `
        -SeveritiesToInclude "High", "Medium"

    Deploys only the solution and High/Medium severity Analytics Rules, skipping Workbooks
    and Automation Rules.

.EXAMPLE
    .\Deploy-SentinelContentHub.ps1 `
        -ResourceGroup "rg-sentinel-prod" `
        -Workspace "law-sentinel-prod" `
        -Region "uksouth" `
        -Solutions "Microsoft 365" `
        -WhatIf

    Performs a dry run showing what would be deployed without making any changes.
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
    [Parameter(Mandatory = $true)]
    [string[]]$Solutions
    ,
    [Parameter(Mandatory = $false)]
    [ValidateSet("High", "Medium", "Low", "Informational")]
    [string[]]$SeveritiesToInclude = @("High", "Medium", "Low", "Informational")
    ,
    [Parameter(Mandatory = $false)]
    [switch]$DisableRules
    ,
    [Parameter(Mandatory = $false)]
    [switch]$SkipSolutionDeployment
    ,
    [Parameter(Mandatory = $false)]
    [switch]$SkipAnalyticsRules
    ,
    [Parameter(Mandatory = $false)]
    [switch]$SkipWorkbooks
    ,
    [Parameter(Mandatory = $false)]
    [switch]$SkipAutomationRules
    ,
    [Parameter(Mandatory = $false)]
    [switch]$SkipHuntingQueries
    ,
    [Parameter(Mandatory = $false)]
    [switch]$ForceSolutionUpdate
    ,
    [Parameter(Mandatory = $false)]
    [switch]$ForceContentDeployment
    ,
    [Parameter(Mandatory = $false)]
    [switch]$ProtectCustomisedRules = $true
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
$script:SentinelApiVersion    = "2025-09-01"
$script:DeploymentApiVersion  = "2024-11-01"
$script:MetadataApiVersion    = "2025-09-01"

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
# Helper: Compare semantic version strings correctly
# ---------------------------------------------------------------------------
function Compare-SemanticVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Version1
        ,
        [Parameter(Mandatory = $true)]
        [string]$Version2
    )

    try {
        $v1Parts = $Version1.Split('.') | ForEach-Object { [int]$_ }
        $v2Parts = $Version2.Split('.') | ForEach-Object { [int]$_ }

        $maxLength = [Math]::Max($v1Parts.Count, $v2Parts.Count)

        for ($i = 0; $i -lt $maxLength; $i++) {
            $p1 = if ($i -lt $v1Parts.Count) { $v1Parts[$i] } else { 0 }
            $p2 = if ($i -lt $v2Parts.Count) { $v2Parts[$i] } else { 0 }

            if ($p1 -gt $p2) { return 1 }
            if ($p1 -lt $p2) { return -1 }
        }

        return 0
    }
    catch {
        # Fall back to string comparison if parsing fails
        return [string]::Compare($Version1, $Version2, [StringComparison]::Ordinal)
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

            if ($_.Exception.Response) {
                $statusCode = [int]$_.Exception.Response.StatusCode
                try {
                    $stream = $_.Exception.Response.GetResponseStream()
                    $reader = [System.IO.StreamReader]::new($stream)
                    $responseBody = $reader.ReadToEnd()
                    $reader.Dispose()
                }
                catch { }
            }

            if (-not $responseBody -and $_.ErrorDetails.Message) {
                $responseBody = $_.ErrorDetails.Message
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

# ---------------------------------------------------------------------------
# Helper: Ensure a mainTemplate is a valid ARM template with required schema
# ---------------------------------------------------------------------------
function ConvertTo-ArmTemplate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$MainTemplate
    )

    # If the template already has $schema, it is a valid ARM template
    if ($MainTemplate.PSObject.Properties.Name -contains '$schema') {
        return $MainTemplate
    }

    # Wrap the mainTemplate resources into a proper ARM template envelope
    $armTemplate = @{
        '$schema'      = "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#"
        contentVersion = "1.0.0.0"
    }

    # Copy parameters if present
    if ($MainTemplate.PSObject.Properties.Name -contains "parameters") {
        $armTemplate.parameters = $MainTemplate.parameters
    }
    else {
        $armTemplate.parameters = @{
            workspace           = @{ type = "string" }
            "workspace-location" = @{ type = "string" }
        }
    }

    # Copy variables if present
    if ($MainTemplate.PSObject.Properties.Name -contains "variables") {
        $armTemplate.variables = $MainTemplate.variables
    }

    # Copy resources
    if ($MainTemplate.PSObject.Properties.Name -contains "resources") {
        $armTemplate.resources = $MainTemplate.resources
    }
    else {
        $armTemplate.resources = @()
    }

    return [PSCustomObject]$armTemplate
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

    # Use provided SubscriptionId or fall back to context
    if ($script:SubscriptionId) {
        Set-AzContext -SubscriptionId $script:SubscriptionId -ErrorAction Stop | Out-Null
        $context = Get-AzContext
    }
    else {
        $script:SubscriptionId = $context.Subscription.Id
    }

    Write-PipelineMessage "Authenticated to subscription: $($context.Subscription.Id) ($($context.Subscription.Name))" -Level Success

    # Build server URL and base URI
    $script:ServerUrl = if ($IsGov) {
        "https://management.usgovcloudapi.net"
    }
    else {
        "https://management.azure.com"
    }

    $script:BaseUri = "$($script:ServerUrl)/subscriptions/$($script:SubscriptionId)/resourceGroups/$ResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$Workspace"

    # Acquire access token
    # Az.Accounts 5.x returns a SecureString by default and renamed parameters.
    # We handle both legacy and current module versions.
    $resourceEndpoint = $script:ServerUrl
    try {
        # Az.Accounts >= 5.0: -ResourceUrl still works but .Token is a SecureString
        $tokenResponse = Get-AzAccessToken -ResourceUrl $resourceEndpoint -ErrorAction Stop

        # Determine whether the Token property is a SecureString or plain string
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
        # Fallback: extract token from the Azure context profile directly
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
# Solution Discovery and Status Assessment
# ---------------------------------------------------------------------------
function Get-ContentHubSolutions {
    [CmdletBinding()]
    param()

    # Wait for Sentinel onboarding to propagate (fresh deployments can take 2-3 minutes)
    Write-PipelineMessage "Verifying Sentinel onboarding status..." -Level Section
    $onboardingUrl = "$($script:BaseUri)/providers/Microsoft.SecurityInsights/onboardingStates/default?api-version=$($script:SentinelApiVersion)"
    $maxWait = 180
    $elapsed = 0
    $interval = 15
    while ($elapsed -lt $maxWait) {
        try {
            $onboardResult = Invoke-SentinelApi -Uri $onboardingUrl -Method Get -Headers $script:AuthHeader -MaxRetries 1
            Write-PipelineMessage "Sentinel onboarding confirmed." -Level Success
            break
        }
        catch {
            $elapsed += $interval
            if ($elapsed -ge $maxWait) {
                throw "Sentinel workspace '$($script:WorkspaceName)' is not onboarded after waiting ${maxWait}s. Ensure Bicep deployment completed successfully."
            }
            Write-PipelineMessage "Workspace not yet onboarded — waiting ${interval}s ($elapsed/${maxWait}s)..." -Level Warning
            Start-Sleep -Seconds $interval
        }
    }

    Write-PipelineMessage "Fetching available Content Hub solutions..." -Level Section

    $catalogUrl = "$($script:BaseUri)/providers/Microsoft.SecurityInsights/contentProductPackages?api-version=$($script:SentinelApiVersion)"
    $catalogResult = Invoke-SentinelApi -Uri $catalogUrl -Method Get -Headers $script:AuthHeader
    $availableSolutions = @(if ($catalogResult.PSObject.Properties.Name -contains "value") { $catalogResult.value } else { @() })

    Write-PipelineMessage "Found $($availableSolutions.Count) solutions in the Content Hub catalogue." -Level Info

    # Fetch installed packages
    $installedUrl = "$($script:BaseUri)/providers/Microsoft.SecurityInsights/contentPackages?api-version=$($script:SentinelApiVersion)"
    try {
        $installedResult = Invoke-SentinelApi -Uri $installedUrl -Method Get -Headers $script:AuthHeader
        $installedPackages = @(if ($installedResult.PSObject.Properties.Name -contains "value") { $installedResult.value } else { @() })
        Write-PipelineMessage "Found $($installedPackages.Count) installed solutions." -Level Info
    }
    catch {
        Write-PipelineMessage "Could not fetch installed solutions: $($_.Exception.Message). Treating all as new." -Level Warning
        $installedPackages = @()
    }

    # Build lookup of installed packages by displayName
    $installedLookup = @{}
    foreach ($pkg in $installedPackages) {
        $name = if ($pkg.properties.PSObject.Properties.Name -contains "displayName") { $pkg.properties.displayName } else { $null }
        if ($name) {
            $installedLookup[$name] = $pkg
        }
    }

    return @{
        Available = $availableSolutions
        Installed = $installedPackages
        InstalledLookup = $installedLookup
    }
}

function Get-SolutionStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SolutionName
        ,
        [Parameter(Mandatory = $true)]
        [array]$AvailableSolutions
        ,
        [Parameter(Mandatory = $true)]
        [hashtable]$InstalledLookup
    )

    $result = @{
        Name             = $SolutionName
        Status           = "NotFound"
        AvailableVersion = $null
        InstalledVersion = $null
        CatalogEntry     = $null
        InstalledPackage = $null
        Action           = "None"
    }

    # Find in catalogue
    $catalogMatch = $AvailableSolutions | Where-Object {
        ($_.properties.PSObject.Properties.Name -contains "displayName") -and
        ($_.properties.displayName -eq $SolutionName)
    } | Select-Object -First 1

    if (-not $catalogMatch) {
        Write-PipelineMessage "Solution '$SolutionName' not found in the Content Hub catalogue." -Level Warning
        return $result
    }

    $result.CatalogEntry = $catalogMatch
    $result.AvailableVersion = if ($catalogMatch.properties.PSObject.Properties.Name -contains "version") {
        $catalogMatch.properties.version
    } else { "0.0.0" }

    # Check if installed
    if ($InstalledLookup.ContainsKey($SolutionName)) {
        $installed = $InstalledLookup[$SolutionName]
        $result.InstalledPackage = $installed

        # Safely access version properties - not all packages expose installedVersion
        if ($installed.properties.PSObject.Properties.Name -contains "installedVersion") {
            $result.InstalledVersion = $installed.properties.installedVersion
        }

        if (-not $result.InstalledVersion -and $installed.properties.PSObject.Properties.Name -contains "version") {
            $result.InstalledVersion = $installed.properties.version
        }

        if (-not $result.InstalledVersion) {
            $result.InstalledVersion = "0.0.0"
        }

        # Compare versions using semantic comparison
        $versionComparison = Compare-SemanticVersion -Version1 $result.AvailableVersion -Version2 $result.InstalledVersion

        if ($versionComparison -gt 0) {
            $result.Status = "UpdateAvailable"
            $result.Action = "Update"
        }
        elseif ($ForceSolutionUpdate) {
            $result.Status = "Installed"
            $result.Action = "ForceUpdate"
        }
        else {
            # Verify solution is truly installed — contentPackages can have stale entries
            # from deleted/recreated workspaces. Cross-check with contentProductPackages
            # which is what Content Hub UI uses to show installed state.
            $catContentId = if ($catalogMatch.properties.PSObject.Properties.Name -contains "contentId") { $catalogMatch.properties.contentId } else { $null }
            $isGenuinelyInstalled = $false
            if ($catContentId) {
                $verifyUrl = "$($script:BaseUri)/providers/Microsoft.SecurityInsights/contentProductPackages/$($catalogMatch.name)?api-version=$($script:SentinelApiVersion)"
                try {
                    $verifyResult = Invoke-SentinelApi -Uri $verifyUrl -Method Get -Headers $script:AuthHeader -MaxRetries 1
                    # Check if the product package reports isInstalled or has valid installedVersion
                    $prodProps = $verifyResult.properties
                    if ($prodProps.PSObject.Properties.Name -contains "isInstalled" -and $prodProps.isInstalled -eq $true) {
                        $isGenuinelyInstalled = $true
                    }
                    elseif ($prodProps.PSObject.Properties.Name -contains "installedVersion" -and $prodProps.installedVersion) {
                        $isGenuinelyInstalled = $true
                    }
                }
                catch { }
            }

            if ($isGenuinelyInstalled) {
                $result.Status = "Installed"
                $result.Action = "None"
            }
            else {
                Write-PipelineMessage "  $SolutionName shows as installed in contentPackages but not in Content Hub — forcing reinstall." -Level Warning
                $result.Status = "Installed"
                $result.Action = "ForceUpdate"
            }
        }
    }
    else {
        $result.Status = "NotInstalled"
        $result.Action = "Install"
    }

    return $result
}

# ---------------------------------------------------------------------------
# Solution Deployment
# ---------------------------------------------------------------------------
function Deploy-Solution {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$SolutionStatus
    )

    $solutionName = $SolutionStatus.Name
    $catalogEntry = $SolutionStatus.CatalogEntry
    $action = $SolutionStatus.Action

    if ($action -eq "None") {
        Write-PipelineMessage "  $solutionName v$($SolutionStatus.InstalledVersion) - no update required." -Level Info
        return $true
    }

    if ($WhatIf) {
        Write-PipelineMessage "  [WhatIf] Would $($action.ToLower()) solution: $solutionName (v$($SolutionStatus.InstalledVersion) -> v$($SolutionStatus.AvailableVersion))" -Level Info
        return $true
    }

    Write-PipelineMessage "  Deploying solution: $solutionName ($action, v$($SolutionStatus.AvailableVersion))..." -Level Info

    # Fetch full packaged content for the solution
    $detailUrl = "$($script:BaseUri)/providers/Microsoft.SecurityInsights/contentProductPackages/$($catalogEntry.name)?api-version=$($script:SentinelApiVersion)"

    try {
        $detailedSolution = Invoke-SentinelApi -Uri $detailUrl -Method Get -Headers $script:AuthHeader
    }
    catch {
        Write-PipelineMessage "  Failed to retrieve package details for $solutionName : $($_.Exception.Message)" -Level Error
        return $false
    }

    $packagedContent = if ($detailedSolution.properties.PSObject.Properties.Name -contains "packagedContent") {
        $detailedSolution.properties.packagedContent
    } else { $null }

    if (-not $packagedContent) {
        Write-PipelineMessage "  No packaged content found for $solutionName. Registering package only." -Level Warning

        # Install the content package registration
        try {
            $catProps = $catalogEntry.properties
            $catContentId = if ($catProps.PSObject.Properties.Name -contains "contentId") { $catProps.contentId } else { $catalogEntry.name }
            $catProductId = if ($catProps.PSObject.Properties.Name -contains "contentProductId") { $catProps.contentProductId } else { $null }
            $catVersion = if ($catProps.PSObject.Properties.Name -contains "version") { $catProps.version } else { "1.0.0" }

            $packageInstallUrl = "$($script:BaseUri)/providers/Microsoft.SecurityInsights/contentPackages/${catContentId}?api-version=$($script:SentinelApiVersion)"
            $packageBody = @{
                properties = @{
                    contentId        = $catContentId
                    contentProductId = $catProductId
                    contentKind      = "Solution"
                    version          = $catVersion
                    displayName      = $solutionName
                }
            } | ConvertTo-Json -Depth 10

            Invoke-SentinelApi -Uri $packageInstallUrl -Method Put -Headers $script:AuthHeader -Body $packageBody | Out-Null
            Write-PipelineMessage "  Registered package for $solutionName." -Level Success
            return $true
        }
        catch {
            Write-PipelineMessage "  Failed to register package for $solutionName : $($_.Exception.Message)" -Level Error
            return $false
        }
    }

    # Strip postDeployment metadata that can cause deployment failures
    foreach ($resource in $packagedContent.resources) {
        if ($resource.properties -and
            $resource.properties.PSObject.Properties.Name -contains "mainTemplate" -and
            $resource.properties.mainTemplate -and
            $resource.properties.mainTemplate.PSObject.Properties.Name -contains "metadata" -and
            $resource.properties.mainTemplate.metadata -and
            $resource.properties.mainTemplate.metadata.PSObject.Properties.Name -contains "postDeployment") {
            $resource.properties.mainTemplate.metadata.postDeployment = $null
        }
    }

    # Deploy via ARM template deployment
    $deploymentName = ("sentinel-$($catalogEntry.name)").Substring(0, [Math]::Min(64, ("sentinel-$($catalogEntry.name)").Length))
    $deploymentUrl = "$($script:ServerUrl)/subscriptions/$($script:SubscriptionId)/resourcegroups/$ResourceGroup/providers/Microsoft.Resources/deployments/${deploymentName}?api-version=$($script:DeploymentApiVersion)"

    $deploymentBody = @{
        properties = @{
            parameters = @{
                "workspace"          = @{ value = $Workspace }
                "workspace-location" = @{ value = $Region }
            }
            template = $packagedContent
            mode     = "Incremental"
        }
    }

    try {
        $jsonBody = $deploymentBody | ConvertTo-Json -EnumsAsStrings -Depth 50 -EscapeHandling EscapeNonAscii
    }
    catch {
        Write-PipelineMessage "  Failed to serialise deployment body for $solutionName : $($_.Exception.Message)" -Level Error
        return $false
    }

    try {
        Invoke-SentinelApi -Uri $deploymentUrl -Method Put -Headers $script:AuthHeader -Body $jsonBody | Out-Null
        Write-PipelineMessage "  Successfully deployed solution: $solutionName v$($SolutionStatus.AvailableVersion)" -Level Success

        # Brief pause to allow deployment propagation
        Start-Sleep -Milliseconds 1500

        return $true
    }
    catch {
        Write-PipelineMessage "  Deployment failed for $solutionName : $($_.Exception.Message)" -Level Error
        return $false
    }
}

# ---------------------------------------------------------------------------
# Analytics Rule Deployment
# ---------------------------------------------------------------------------
function Get-ExistingAnalyticsRules {
    [CmdletBinding()]
    param()

    Write-PipelineMessage "Fetching existing Analytics Rules..." -Level Info

    $rulesUrl = "$($script:BaseUri)/providers/Microsoft.SecurityInsights/alertRules?api-version=$($script:SentinelApiVersion)"
    $ruleList = [System.Collections.Generic.List[object]]::new()
    $result = Invoke-SentinelApi -Uri $rulesUrl -Method Get -Headers $script:AuthHeader
    if ($result.PSObject.Properties.Name -contains "value") {
        foreach ($r in $result.value) { $ruleList.Add($r) }
    }

    while ($result.PSObject.Properties.Name -contains "nextLink" -and $result.nextLink) {
        $result = Invoke-SentinelApi -Uri $result.nextLink -Method Get -Headers $script:AuthHeader
        if ($result.PSObject.Properties.Name -contains "value") {
            foreach ($r in $result.value) { $ruleList.Add($r) }
        }
    }

    $rules = @($ruleList)
    Write-PipelineMessage "Found $($rules.Count) existing Analytics Rules." -Level Info
    return ,$rules
}

function Test-RuleIsCustomised {
    <#
    .SYNOPSIS
        Detects whether an existing Analytics Rule has been modified from its OoB template.
    .DESCRIPTION
        Compares the deployed rule against its content template to identify local customisations
        such as modified queries, thresholds, entity mappings, or scheduling parameters.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$ExistingRule
        ,
        [Parameter(Mandatory = $true)]
        [object]$TemplateProperties
    )

    $isCustomised = $false
    $modifications = @()

    $existingProps = $ExistingRule.properties

    # Compare KQL query
    if ($existingProps.PSObject.Properties.Name -contains "query" -and
        $TemplateProperties.PSObject.Properties.Name -contains "query") {
        $existingQuery = ($existingProps.query -replace '\s+', ' ').Trim()
        $templateQuery = ($TemplateProperties.query -replace '\s+', ' ').Trim()
        if ($existingQuery -ne $templateQuery) {
            $isCustomised = $true
            $modifications += "KQL query"
        }
    }

    # Compare query frequency
    if ($existingProps.PSObject.Properties.Name -contains "queryFrequency" -and
        $TemplateProperties.PSObject.Properties.Name -contains "queryFrequency") {
        if ($existingProps.queryFrequency -ne $TemplateProperties.queryFrequency) {
            $isCustomised = $true
            $modifications += "queryFrequency"
        }
    }

    # Compare query period
    if ($existingProps.PSObject.Properties.Name -contains "queryPeriod" -and
        $TemplateProperties.PSObject.Properties.Name -contains "queryPeriod") {
        if ($existingProps.queryPeriod -ne $TemplateProperties.queryPeriod) {
            $isCustomised = $true
            $modifications += "queryPeriod"
        }
    }

    # Compare trigger threshold
    if ($existingProps.PSObject.Properties.Name -contains "triggerThreshold" -and
        $TemplateProperties.PSObject.Properties.Name -contains "triggerThreshold") {
        if ($existingProps.triggerThreshold -ne $TemplateProperties.triggerThreshold) {
            $isCustomised = $true
            $modifications += "triggerThreshold"
        }
    }

    # Compare trigger operator
    if ($existingProps.PSObject.Properties.Name -contains "triggerOperator" -and
        $TemplateProperties.PSObject.Properties.Name -contains "triggerOperator") {
        if ($existingProps.triggerOperator -ne $TemplateProperties.triggerOperator) {
            $isCustomised = $true
            $modifications += "triggerOperator"
        }
    }

    # Compare severity
    if ($existingProps.PSObject.Properties.Name -contains "severity" -and
        $TemplateProperties.PSObject.Properties.Name -contains "severity") {
        if ($existingProps.severity -ne $TemplateProperties.severity) {
            $isCustomised = $true
            $modifications += "severity"
        }
    }

    # Note: entityMappings are NOT compared for customisation detection.
    # JSON serialisation differences between API responses and templates
    # cause false positives on every rule. Entity mappings are rarely
    # manually customised and will be updated with the template version.

    return @{
        IsCustomised  = $isCustomised
        Modifications = $modifications
    }
}

function Write-RuleMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Template,
        [Parameter(Mandatory)][string]$RuleId,
        [Parameter(Mandatory)][string]$RuleName,
        [string]$TemplateName,
        [string]$TemplateVersion,
        [array]$AvailableSolutions,
        [hashtable]$SolutionIdLookup,
        [hashtable]$SolutionDetailLookup,
        [string]$DisplayName
    )

    $pkgId = if ($Template.properties.PSObject.Properties.Name -contains "packageId") { $Template.properties.packageId } else { $null }
    if (-not $pkgId) {
        Write-PipelineMessage "    Metadata skip: no packageId for $DisplayName" -Level Warning
        return
    }

    # Use the pre-built solution detail lookup (packageId -> {name, contentId})
    if ($SolutionDetailLookup -and $SolutionDetailLookup.ContainsKey($pkgId)) {
        $solDetail = $SolutionDetailLookup[$pkgId]
        $solDisplayName = $solDetail.Name
        $solContentId = $solDetail.ContentId
    }
    elseif ($SolutionIdLookup -and $SolutionIdLookup.ContainsKey($pkgId)) {
        # Fallback to basic lookup
        $solDisplayName = $SolutionIdLookup[$pkgId]
        $solContentId = $pkgId
    }
    else {
        Write-PipelineMessage "    Metadata skip: packageId '$pkgId' not in solution lookup for $DisplayName" -Level Warning
        return
    }

    # Validate parentId has leading slash (required by API)
    if ($RuleId -and -not $RuleId.StartsWith('/')) {
        $RuleId = "/$RuleId"
    }

    $metaBody = @{
        properties = @{
            contentId = $TemplateName
            parentId  = $RuleId
            kind      = "AnalyticsRule"
            version   = if ($TemplateVersion) { $TemplateVersion } else { "1.0.0" }
            source    = @{
                kind     = "Solution"
                name     = $solDisplayName
                sourceId = $solContentId
            }
        }
    } | ConvertTo-Json -Depth 10 -Compress

    $metaUri = "$($script:BaseUri)/providers/Microsoft.SecurityInsights/metadata/analyticsrule-${RuleName}?api-version=$($script:MetadataApiVersion)"

    try {
        Invoke-SentinelApi -Uri $metaUri -Method Put -Headers $script:AuthHeader -Body $metaBody | Out-Null
        Write-PipelineMessage "    Metadata linked: $DisplayName -> $solDisplayName" -Level Info
        $script:MetadataLinked++
    }
    catch {
        $metaError = $_.Exception.Message
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $metaError = $_.ErrorDetails.Message }
        Write-PipelineMessage "    Metadata FAILED for $DisplayName : $metaError" -Level Warning
        Write-PipelineMessage "    Metadata body: $metaBody" -Level Warning
        Write-PipelineMessage "    Metadata URI: $metaUri" -Level Warning
        $script:MetadataFailed++
    }
}

function Deploy-AnalyticsRules {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$SolutionNames
        ,
        [Parameter(Mandatory = $true)]
        [array]$AvailableSolutions
    )

    Write-PipelineMessage "Deploying Analytics Rules..." -Level Section

    # Wait for solution templates to propagate
    Write-PipelineMessage "Waiting for solution content templates to propagate (60s)..." -Level Info
    Start-Sleep -Seconds 60

    # Fetch content templates for Analytics Rules (must expand mainTemplate)
    $templatesUrl = "$($script:BaseUri)/providers/Microsoft.SecurityInsights/contentTemplates?api-version=$($script:SentinelApiVersion)&`$filter=(properties/contentKind eq 'AnalyticsRule')&`$expand=properties/mainTemplate"
    try {
        $templateList = [System.Collections.Generic.List[object]]::new()
        $templatesResult = Invoke-SentinelApi -Uri $templatesUrl -Method Get -Headers $script:AuthHeader
        if ($templatesResult.PSObject.Properties.Name -contains "value") {
            foreach ($t in $templatesResult.value) { $templateList.Add($t) }
        }

        # Handle pagination
        while ($templatesResult.PSObject.Properties.Name -contains "nextLink" -and $templatesResult.nextLink) {
            $templatesResult = Invoke-SentinelApi -Uri $templatesResult.nextLink -Method Get -Headers $script:AuthHeader
            if ($templatesResult.PSObject.Properties.Name -contains "value") {
                foreach ($t in $templatesResult.value) { $templateList.Add($t) }
            }
        }

        $allTemplates = @($templateList)
        Write-PipelineMessage "Found $($allTemplates.Count) Analytics Rule templates." -Level Info
    }
    catch {
        Write-PipelineMessage "Failed to fetch Analytics Rule templates: $($_.Exception.Message)" -Level Error
        return @{ Deployed = 0; Updated = 0; Skipped = 0; CustomisedSkipped = 0; Failed = 0 }
    }

    # Build solution ID lookup (case-insensitive name matching)
    $SolutionNamesLower = @($SolutionNames | ForEach-Object { $_.ToLower() })
    $solutionIdLookup = @{}
    foreach ($sol in $AvailableSolutions) {
        $solName = if ($sol.properties.PSObject.Properties.Name -contains "displayName") { $sol.properties.displayName } else { $null }
        if ($solName -and $SolutionNamesLower -contains $solName.ToLower()) {
            if ($sol.properties.PSObject.Properties.Name -contains "contentId" -and $sol.properties.contentId) {
                $solutionIdLookup[$sol.properties.contentId] = $solName
            }
            if ($sol.name) { $solutionIdLookup[$sol.name] = $solName }
        }
    }

    # Build detailed solution lookup: packageId -> {Name, ContentId}
    $solutionDetailLookup = @{}
    foreach ($sol in $AvailableSolutions) {
        $solName = if ($sol.properties.PSObject.Properties.Name -contains "displayName") { $sol.properties.displayName } else { $null }
        $solCid = if ($sol.properties.PSObject.Properties.Name -contains "contentId") { $sol.properties.contentId } else { $sol.name }
        if ($solName -and $solCid) {
            if ($solutionIdLookup.ContainsKey($solCid)) {
                $solutionDetailLookup[$solCid] = @{ Name = $solName; ContentId = $solCid }
            }
            if ($sol.name -and $solutionIdLookup.ContainsKey($sol.name)) {
                $solutionDetailLookup[$sol.name] = @{ Name = $solName; ContentId = $solCid }
            }
        }
    }
    Write-PipelineMessage "Solution detail lookup: $($solutionDetailLookup.Count) entries for metadata linking." -Level Info

    # Filter templates to target solutions
    $targetTemplates = @($allTemplates | Where-Object {
        $hasPkgId = $_.properties.PSObject.Properties.Name -contains "packageId"
        $hasPkgId -and $solutionIdLookup.ContainsKey($_.properties.packageId)
    })

    Write-PipelineMessage "Found $($targetTemplates.Count) Analytics Rule templates for target solutions." -Level Info

    if ($targetTemplates.Count -eq 0) {
        Write-PipelineMessage "No Analytics Rule templates found for the specified solutions." -Level Warning
        return @{ Deployed = 0; Updated = 0; Skipped = 0; CustomisedSkipped = 0; Failed = 0 }
    }

    # Fetch existing rules
    $existingRules = Get-ExistingAnalyticsRules

    # Build lookup tables
    $rulesByTemplate = @{}
    $rulesByName = @{}
    foreach ($rule in $existingRules) {
        if (($rule.properties.PSObject.Properties.Name -contains "alertRuleTemplateName") -and $rule.properties.alertRuleTemplateName) {
            $rulesByTemplate[$rule.properties.alertRuleTemplateName] = $rule
        }
        if (($rule.properties.PSObject.Properties.Name -contains "displayName") -and $rule.properties.displayName) {
            $rulesByName[$rule.properties.displayName] = $rule
        }
    }

    # Process each template
    $counters = @{
        Deployed          = 0
        Updated           = 0
        Skipped           = 0
        CustomisedSkipped = 0
        Deprecated        = 0
        Failed            = 0
    }

    $baseAlertUri = "$($script:BaseUri)/providers/Microsoft.SecurityInsights/alertRules/"

    foreach ($template in $targetTemplates) {
        # Safely check for mainTemplate - it may not be present even with $expand
        $hasMainTemplate = ($template.properties.PSObject.Properties.Name -contains "mainTemplate") -and
                           ($null -ne $template.properties.mainTemplate)

        if (-not $hasMainTemplate) {
            $counters.Skipped++
            continue
        }

        $mainTemplate = $template.properties.mainTemplate

        $hasResources = ($mainTemplate.PSObject.Properties.Name -contains "resources") -and
                        ($null -ne $mainTemplate.resources) -and
                        ($mainTemplate.resources.Count -gt 0)

        if (-not $hasResources) {
            $tmplName = if ($template.properties.PSObject.Properties.Name -contains "displayName") { $template.properties.displayName } else { $template.name }
            Write-PipelineMessage "  Skipping template with no resources: $tmplName" -Level Debug
            $counters.Skipped++
            continue
        }

        $templateResources = $mainTemplate.resources

        # Safely access the first resource's properties
        $firstResource = $templateResources[0]
        $hasProps = ($firstResource.PSObject.Properties.Name -contains "properties") -and
                    ($null -ne $firstResource.properties)

        if (-not $hasProps) {
            $counters.Skipped++
            continue
        }

        $ruleProperties = $firstResource.properties
        $displayName = if ($ruleProperties.PSObject.Properties.Name -contains "displayName") { $ruleProperties.displayName } else { $null }
        $severity = if ($ruleProperties.PSObject.Properties.Name -contains "severity") { $ruleProperties.severity } else { $null }
        $kind = if ($firstResource.PSObject.Properties.Name -contains "kind") { $firstResource.kind } else { "Scheduled" }

        # Use the content template's contentId (GUID) rather than the ARM resource name (which may be an ARM expression)
        $templateContentId = if ($template.properties.PSObject.Properties.Name -contains "contentId") { $template.properties.contentId } else { $null }
        $templateName = if ($templateContentId) { $templateContentId } elseif ($firstResource.PSObject.Properties.Name -contains "name") { $firstResource.name } else { $null }

        # Extract template version - check the template properties first, then metadata resource
        $templateVersion = if ($template.properties.PSObject.Properties.Name -contains "version") { $template.properties.version } else { $null }
        if ($templateResources.Count -gt 1) {
            $secondResource = $templateResources[1]
            if ($secondResource.PSObject.Properties.Name -contains "properties" -and
                $null -ne $secondResource.properties -and
                $secondResource.properties.PSObject.Properties.Name -contains "version") {
                $templateVersion = $secondResource.properties.version
            }
        }

        # Skip deprecated rules
        if ($displayName -and $displayName -match "\[Deprecated\]") {
            Write-PipelineMessage "  Skipping deprecated rule: $displayName" -Level Debug
            $counters.Deprecated++
            continue
        }

        # Filter by severity
        if ($SeveritiesToInclude -and $severity -and $SeveritiesToInclude -notcontains $severity) {
            $counters.Skipped++
            continue
        }

        # Resolve the parent solution name for this template
        $templatePackageId = if ($template.properties.PSObject.Properties.Name -contains "packageId") { $template.properties.packageId } else { $null }
        $parentSolutionName = if ($templatePackageId -and $solutionIdLookup.ContainsKey($templatePackageId)) { $solutionIdLookup[$templatePackageId] } else { $null }

        # Check if this rule belongs to a freshly deployed solution
        $isFromNewSolution = $parentSolutionName -and $script:NewlyDeployedSolutions -and ($script:NewlyDeployedSolutions -contains $parentSolutionName)

        # Check if rule already exists
        $existingRule = $null
        $needsUpdate = $false

        if ($templateName -and $rulesByTemplate.ContainsKey($templateName)) {
            $existingRule = $rulesByTemplate[$templateName]
            $currentVersion = if ($existingRule.properties.PSObject.Properties.Name -contains "templateVersion") {
                $existingRule.properties.templateVersion
            } else { $null }

            # If DisableRules is set and the existing rule is enabled, force an update to disable it
            $existingEnabled = $true
            if ($existingRule.properties.PSObject.Properties.Name -contains "enabled") {
                $existingEnabled = $existingRule.properties.enabled
            }
            $needsDisable = $DisableRules -and $existingEnabled

            # Force-process content from freshly installed solutions
            if ($isFromNewSolution) {
                $needsUpdate = $true
            }
            elseif ($needsDisable) {
                $needsUpdate = $true
            }
            elseif ($currentVersion -and $templateVersion) {
                $versionCmp = Compare-SemanticVersion -Version1 $templateVersion -Version2 $currentVersion
                if ($versionCmp -gt 0) {
                    $needsUpdate = $true
                }
                elseif (-not $ForceContentDeployment) {
                    # Ensure metadata is correct even for skipped rules
                    Write-RuleMetadata -Template $template -RuleId $existingRule.id -RuleName $existingRule.name `
                        -TemplateName $templateName -TemplateVersion $templateVersion `
                        -AvailableSolutions $AvailableSolutions -SolutionIdLookup $solutionIdLookup -SolutionDetailLookup $solutionDetailLookup `
                        -DisplayName $displayName
                    $counters.Skipped++
                    continue
                }
                else {
                    $needsUpdate = $true
                }
            }
            elseif (-not $ForceContentDeployment) {
                # Ensure metadata is correct even for skipped rules
                Write-RuleMetadata -Template $template -RuleId $existingRule.id -RuleName $existingRule.name `
                    -TemplateName $templateName -TemplateVersion $templateVersion `
                    -AvailableSolutions $AvailableSolutions -SolutionIdLookup $solutionIdLookup -SolutionDetailLookup $solutionDetailLookup `
                    -DisplayName $displayName
                $counters.Skipped++
                continue
            }
            else {
                $needsUpdate = $true
            }
        }
        elseif ($displayName -and $rulesByName.ContainsKey($displayName)) {
            # Rule exists by name but not linked to template - treat as customised
            if ($ProtectCustomisedRules) {
                Write-PipelineMessage "  CUSTOMISED RULE DETECTED (name match, no template link): $displayName - Skipping update." -Level Warning
                $counters.CustomisedSkipped++
                continue
            }
            $existingRule = $rulesByName[$displayName]
            $needsUpdate = $true
        }

        # If updating, check for local customisations
        if ($needsUpdate -and $existingRule -and $ProtectCustomisedRules) {
            $customCheck = Test-RuleIsCustomised -ExistingRule $existingRule -TemplateProperties $ruleProperties

            if ($customCheck.IsCustomised) {
                $modList = $customCheck.Modifications -join ", "
                Write-PipelineMessage "  CUSTOMISED RULE DETECTED: $displayName - Modified fields: $modList - Skipping update." -Level Warning
                $counters.CustomisedSkipped++
                continue
            }
        }

        # Build the rule body
        if ($WhatIf) {
            $action = if ($needsUpdate) { "update" } else { "deploy" }
            Write-PipelineMessage "  [WhatIf] Would $action rule: $displayName ($severity)" -Level Info
            if ($needsUpdate) { $counters.Updated++ } else { $counters.Deployed++ }
            continue
        }

        # Prepare rule properties for deployment
        $deployProperties = $ruleProperties.PSObject.Copy()

        # Strip ARM template artifacts that are not valid in the alertRules API body
        foreach ($armProp in @('apiVersion', 'type', 'name', 'id', 'dependsOn', 'metadata', 'contentId', 'contentKind', 'contentProductId')) {
            if ($deployProperties.PSObject.Properties.Name -contains $armProp) {
                $deployProperties.PSObject.Properties.Remove($armProp)
            }
        }

        # Set enabled state based on DisableRules switch
        if ($DisableRules) {
            $deployProperties | Add-Member -NotePropertyName "enabled" -NotePropertyValue $false -Force
        }
        else {
            if (-not ($deployProperties.PSObject.Properties.Name -contains "enabled")) {
                $deployProperties | Add-Member -NotePropertyName "enabled" -NotePropertyValue $true -Force
            }
        }

        # Link to template
        $deployProperties | Add-Member -NotePropertyName "alertRuleTemplateName" -NotePropertyValue $templateName -Force
        $deployProperties | Add-Member -NotePropertyName "templateVersion" -NotePropertyValue $templateVersion -Force

        # NRT rules do not support queryFrequency or queryPeriod — strip them
        if ($kind -eq "NRT") {
            if ($deployProperties.PSObject.Properties.Name -contains "queryFrequency") {
                $deployProperties.PSObject.Properties.Remove("queryFrequency")
            }
            if ($deployProperties.PSObject.Properties.Name -contains "queryPeriod") {
                $deployProperties.PSObject.Properties.Remove("queryPeriod")
            }
            if ($deployProperties.PSObject.Properties.Name -contains "triggerOperator") {
                $deployProperties.PSObject.Properties.Remove("triggerOperator")
            }
            if ($deployProperties.PSObject.Properties.Name -contains "triggerThreshold") {
                $deployProperties.PSObject.Properties.Remove("triggerThreshold")
            }

            # If updating an existing NRT rule created with an older API version,
            # delete it first and create fresh — Azure routes PUTs through the original
            # api-version which may not support NRT kind
            if ($needsUpdate -and $existingRule) {
                try {
                    $deleteUri = "${baseAlertUri}$($existingRule.name)?api-version=$($script:SentinelApiVersion)"
                    Invoke-SentinelApi -Uri $deleteUri -Method Delete -Headers $script:AuthHeader | Out-Null
                }
                catch {
                    Write-PipelineMessage "  Warning: Could not delete existing NRT rule $displayName for recreation: $($_.Exception.Message)" -Level Warning
                }
                $existingRule = $null
                $needsUpdate = $false
            }
        }

        # Ensure entityMappings is an array and within API limit (max 5)
        if ($deployProperties.PSObject.Properties.Name -contains "entityMappings") {
            if ($deployProperties.entityMappings -and $deployProperties.entityMappings -isnot [System.Array]) {
                $deployProperties.entityMappings = @($deployProperties.entityMappings)
            }
            if ($deployProperties.entityMappings -and $deployProperties.entityMappings.Count -gt 5) {
                $deployProperties.entityMappings = @($deployProperties.entityMappings | Select-Object -First 5)
            }
        }

        # Fix incidentConfiguration groupingConfiguration
        if ($deployProperties.PSObject.Properties.Name -contains "incidentConfiguration") {
            $incidentConfig = $deployProperties.incidentConfiguration
            if ($incidentConfig -and $incidentConfig.PSObject.Properties.Name -contains "groupingConfiguration") {
                $groupConfig = $incidentConfig.groupingConfiguration
                if ($groupConfig) {
                    if (-not ($groupConfig.PSObject.Properties.Name -contains "matchingMethod")) {
                        $groupConfig | Add-Member -NotePropertyName "matchingMethod" -NotePropertyValue "AllEntities" -Force
                    }
                    if ($groupConfig.PSObject.Properties.Name -contains "lookbackDuration") {
                        $lookback = $groupConfig.lookbackDuration
                        if ($lookback -match "^(\d+)(h|d|m)$") {
                            $timeValue = $matches[1]
                            $timeUnit = $matches[2]
                            $isoDuration = switch ($timeUnit) {
                                "h" { "PT${timeValue}H" }
                                "d" { "P${timeValue}D" }
                                "m" { "PT${timeValue}M" }
                            }
                            $groupConfig.lookbackDuration = $isoDuration
                        }
                    }
                }
                elseif (-not $groupConfig) {
                    $incidentConfig | Add-Member -NotePropertyName "groupingConfiguration" -NotePropertyValue @{
                        matchingMethod   = "AllEntities"
                        lookbackDuration = "PT1H"
                    } -Force
                }
            }
        }

        $ruleBody = @{
            kind       = $kind
            properties = $deployProperties
        }

        $ruleId = if ($needsUpdate -and $existingRule) { $existingRule.name } else { (New-Guid).Guid }
        $alertUri = "${baseAlertUri}${ruleId}?api-version=$($script:SentinelApiVersion)"

        try {
            $jsonBody = $ruleBody | ConvertTo-Json -Depth 50 -Compress
            $ruleResult = Invoke-SentinelApi -Uri $alertUri -Method Put -Headers $script:AuthHeader -Body $jsonBody

            if ($needsUpdate) {
                Write-PipelineMessage "  Updated rule: $displayName ($severity)" -Level Success
                $counters.Updated++
            }
            else {
                Write-PipelineMessage "  Deployed rule: $displayName ($severity)" -Level Success
                $counters.Deployed++
            }

            # Create metadata to link rule back to solution
            $resultId = if ($ruleResult.PSObject.Properties.Name -contains "id" -and $ruleResult.id) {
                $ruleResult.id
            } else {
                "${baseAlertUri}${ruleId}"
            }
            $resultName = if ($ruleResult.PSObject.Properties.Name -contains "name" -and $ruleResult.name) {
                $ruleResult.name
            } else {
                $ruleId
            }
            Write-RuleMetadata -Template $template -RuleId $resultId -RuleName $resultName `
                -TemplateName $templateName -TemplateVersion $templateVersion `
                -AvailableSolutions $AvailableSolutions -SolutionIdLookup $solutionIdLookup -SolutionDetailLookup $solutionDetailLookup `
                -DisplayName $displayName

            Start-Sleep -Milliseconds 500
        }
        catch {
            $errorMessage = $_.Exception.Message
            $errorDetail = ""
            if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
                $errorDetail = $_.ErrorDetails.Message
            }

            $combinedError = "$errorMessage $errorDetail"

            if ($combinedError -match "One of the tables does not exist") {
                Write-PipelineMessage "  Skipping $displayName - missing tables in the environment." -Level Warning
                $counters.Skipped++
            }
            elseif ($combinedError -match "The given column") {
                Write-PipelineMessage "  Skipping $displayName - missing column in the query." -Level Warning
                $counters.Skipped++
            }
            elseif ($combinedError -match "FailedToResolveScalarExpression|SemanticError") {
                Write-PipelineMessage "  Skipping $displayName - invalid expression in the query." -Level Warning
                $counters.Skipped++
            }
            elseif ($combinedError -match "InvalidTemplate|DeploymentFailed") {
                Write-PipelineMessage "  Skipping $displayName - template validation error." -Level Warning
                $counters.Skipped++
            }
            elseif ($combinedError -match "BadRequest|400") {
                $nrtHint = if ($kind -eq "NRT") { " NRT rules must not include queryFrequency/queryPeriod." } else { "" }
                $detail = $combinedError.Substring(0, [Math]::Min(300, $combinedError.Length))
                Write-PipelineMessage "  Skipping $displayName ($kind) - bad request.$nrtHint Detail: $detail" -Level Warning
                $counters.Skipped++
            }
            else {
                Write-PipelineMessage "  Failed to deploy rule: $displayName - $combinedError" -Level Error
                $counters.Failed++
            }
        }
    }

    return $counters
}

# ---------------------------------------------------------------------------
# Workbook Deployment
# ---------------------------------------------------------------------------
function Deploy-Workbooks {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$SolutionNames
        ,
        [Parameter(Mandatory = $true)]
        [array]$AvailableSolutions
    )

    Write-PipelineMessage "Deploying Workbooks..." -Level Section

    # Fetch workbook content templates (details fetched individually per workbook)
    $templatesUrl = "$($script:BaseUri)/providers/Microsoft.SecurityInsights/contentTemplates?api-version=$($script:SentinelApiVersion)&`$filter=(properties/contentKind eq 'Workbook') or (properties/contentKind eq 'WorkbookTemplate')&`$expand=properties/mainTemplate"
    try {
        $templatesResult = Invoke-SentinelApi -Uri $templatesUrl -Method Get -Headers $script:AuthHeader
        $allTemplates = @(if ($templatesResult.PSObject.Properties.Name -contains "value") { $templatesResult.value } else { @() })

        while ($templatesResult.PSObject.Properties.Name -contains "nextLink" -and $templatesResult.nextLink) {
            $templatesResult = Invoke-SentinelApi -Uri $templatesResult.nextLink -Method Get -Headers $script:AuthHeader
            if ($templatesResult.PSObject.Properties.Name -contains "value") {
                $allTemplates += $templatesResult.value
            }
        }

        Write-PipelineMessage "Found $($allTemplates.Count) Workbook templates." -Level Info
    }
    catch {
        Write-PipelineMessage "Failed to fetch Workbook templates: $($_.Exception.Message)" -Level Error
        return @{ Deployed = 0; Updated = 0; Skipped = 0; Failed = 0 }
    }

    # Build solution ID lookup (case-insensitive name matching)
    $SolutionNamesLower = @($SolutionNames | ForEach-Object { $_.ToLower() })
    $solutionIdLookup = @{}
    foreach ($sol in $AvailableSolutions) {
        $solName = if ($sol.properties.PSObject.Properties.Name -contains "displayName") { $sol.properties.displayName } else { $null }
        if ($solName -and $SolutionNamesLower -contains $solName.ToLower()) {
            if (($sol.properties.PSObject.Properties.Name -contains "contentId") -and $sol.properties.contentId) {
                $solutionIdLookup[$sol.properties.contentId] = $solName
            }
            if ($sol.name) { $solutionIdLookup[$sol.name] = $solName }
        }
    }

    # Filter to target solutions
    $targetTemplates = @($allTemplates | Where-Object {
        ($_.properties.PSObject.Properties.Name -contains "packageId") -and
        $solutionIdLookup.ContainsKey($_.properties.packageId)
    })

    Write-PipelineMessage "Found $($targetTemplates.Count) Workbook templates for target solutions." -Level Info

    if ($targetTemplates.Count -eq 0) {
        return @{ Deployed = 0; Updated = 0; Skipped = 0; Failed = 0 }
    }

    # Fetch existing workbook metadata to check what is already deployed
    $metadataUrl = "$($script:BaseUri)/providers/Microsoft.SecurityInsights/metadata?api-version=$($script:SentinelApiVersion)&`$filter=(properties/kind eq 'Workbook')"
    $existingWorkbooks = @()
    try {
        $metadataResult = Invoke-SentinelApi -Uri $metadataUrl -Method Get -Headers $script:AuthHeader
        $existingWorkbooks = @(if ($metadataResult.PSObject.Properties.Name -contains "value") { $metadataResult.value } else { @() })
        Write-PipelineMessage "Found $($existingWorkbooks.Count) existing workbook metadata entries." -Level Info
    }
    catch {
        Write-PipelineMessage "Could not fetch workbook metadata: $($_.Exception.Message)" -Level Warning
    }

    # Build lookup by contentId — only include metadata that points at a saved workbook
    # resource. Content Hub solution install writes metadata whose parentId points at a
    # contentTemplate; that means the template is registered but no workbook has been
    # saved to the workspace, so we must deploy it ourselves rather than treat it as done.
    $existingByContentId = @{}
    foreach ($wb in $existingWorkbooks) {
        if ($wb.properties.PSObject.Properties.Name -notcontains "contentId") { continue }
        $parentId = if ($wb.properties.PSObject.Properties.Name -contains "parentId") { $wb.properties.parentId } else { $null }
        if (-not ($parentId -match '/providers/Microsoft\.Insights/workbooks/')) { continue }
        $existingByContentId[$wb.properties.contentId] = $wb
    }

    $counters = @{ Deployed = 0; Updated = 0; Skipped = 0; Failed = 0 }

    foreach ($template in $targetTemplates) {
        $displayName = if ($template.properties.PSObject.Properties.Name -contains "displayName") { $template.properties.displayName } else { "Unknown" }
        $contentId = if ($template.properties.PSObject.Properties.Name -contains "contentId") { $template.properties.contentId } else { $null }
        $templateVersion = if ($template.properties.PSObject.Properties.Name -contains "version") { $template.properties.version } else { $null }

        # Skip deprecated
        if ($displayName -match "\[Deprecated\]") {
            $counters.Skipped++
            continue
        }

        # Check if this workbook belongs to a freshly deployed solution
        $wbPackageId = if ($template.properties.PSObject.Properties.Name -contains "packageId") { $template.properties.packageId } else { $null }
        $wbParentSolution = if ($wbPackageId -and $solutionIdLookup.ContainsKey($wbPackageId)) { $solutionIdLookup[$wbPackageId] } else { $null }
        $isFromNewSolution = $wbParentSolution -and $script:NewlyDeployedSolutions -and ($script:NewlyDeployedSolutions -contains $wbParentSolution)

        # Check if already deployed
        $existingMeta = if ($contentId) { $existingByContentId[$contentId] } else { $null }
        $needsUpdate = $false

        if ($existingMeta -and -not $ForceContentDeployment -and -not $isFromNewSolution) {
            # Check version
            $existingVersion = if ($existingMeta.properties.PSObject.Properties.Name -contains "version") { $existingMeta.properties.version } else { $null }
            if ($existingVersion -and $templateVersion -and $existingVersion -eq $templateVersion) {
                $counters.Skipped++
                continue
            }
            $needsUpdate = $true
        }
        elseif ($existingMeta) {
            $needsUpdate = $true
        }

        if ($WhatIf) {
            $action = if ($needsUpdate) { "update" } else { "deploy" }
            Write-PipelineMessage "  [WhatIf] Would $action workbook: $displayName" -Level Info
            if ($needsUpdate) { $counters.Updated++ } else { $counters.Deployed++ }
            continue
        }

        # Fetch detailed template — try contentId first, fall back to name
        $detailedTemplate = $null
        $templateIdentifiers = @($contentId, $template.name) | Where-Object { $_ }

        foreach ($tmplId in $templateIdentifiers) {
            $detailUrl = "$($script:BaseUri)/providers/Microsoft.SecurityInsights/contentTemplates/${tmplId}?api-version=$($script:SentinelApiVersion)"
            try {
                $detailedTemplate = Invoke-SentinelApi -Uri $detailUrl -Method Get -Headers $script:AuthHeader
                break
            }
            catch {
                continue
            }
        }

        if (-not $detailedTemplate) {
            # Fall back to the listing template itself — some templates include mainTemplate inline
            if ($template.properties.PSObject.Properties.Name -contains "mainTemplate" -and $template.properties.mainTemplate) {
                $detailedTemplate = $template
            }
            else {
                Write-PipelineMessage "  Failed to fetch template details for workbook: $displayName — skipping" -Level Warning
                $counters.Failed++
                continue
            }
        }

        $hasMainTemplate = ($detailedTemplate.properties.PSObject.Properties.Name -contains "mainTemplate") -and
                           ($null -ne $detailedTemplate.properties.mainTemplate)
        if (-not $hasMainTemplate) {
            Write-PipelineMessage "  No mainTemplate for workbook: $displayName — skipping" -Level Warning
            $counters.Skipped++
            continue
        }

        $mainResources = $detailedTemplate.properties.mainTemplate.resources

        # Find the workbook resource and metadata resource
        $workbookResource = $mainResources | Where-Object {
            ($_.PSObject.Properties.Name -contains "type") -and ($_.type -eq 'Microsoft.Insights/workbooks')
        } | Select-Object -First 1

        $metadataResource = $mainResources | Where-Object {
            ($_.PSObject.Properties.Name -contains "type") -and ($_.type -eq 'Microsoft.OperationalInsights/workspaces/providers/metadata')
        } | Select-Object -First 1

        if (-not $workbookResource) {
            Write-PipelineMessage "  No workbook resource found in template: $displayName" -Level Warning
            $counters.Failed++
            continue
        }

        # Generate GUID for the workbook — reuse existing GUID when updating to avoid orphans
        $guid = if ($needsUpdate -and $existingMeta -and ($existingMeta.properties.PSObject.Properties.Name -contains "parentId")) {
            if ($existingMeta.properties.parentId -match '/([^/]+)$') { $matches[1] } else { (New-Guid).Guid }
        }
        else {
            (New-Guid).Guid
        }

        # Extract serializedData from the workbook resource properties
        $wbProps = $workbookResource.properties
        $serializedData = if ($wbProps -and ($wbProps.PSObject.Properties.Name -contains "serializedData")) {
            $wbProps.serializedData
        }
        else {
            $null
        }

        if (-not $serializedData) {
            Write-PipelineMessage "  No serializedData found in workbook template: $displayName — skipping" -Level Warning
            $counters.Skipped++
            continue
        }

        $wbDisplayName = if ($wbProps -and ($wbProps.PSObject.Properties.Name -contains "displayName")) {
            $wbProps.displayName
        }
        else {
            $displayName
        }

        # Workspace resource ID (no https://management.azure.com prefix) — Sentinel uses this
        # tag to bind the workbook to the workspace; with the host prefix it won't surface in
        # the Sentinel Workbooks blade even though the Azure Monitor resource is created.
        $workspaceResourceId = $script:BaseUri.Replace($script:ServerUrl, "")

        # Build a clean workbook resource body — direct PUT to Microsoft.Insights/workbooks
        $workbookBody = @{
            location = $Region
            kind     = "shared"
            properties = @{
                displayName    = $wbDisplayName
                serializedData = $serializedData
                version        = "1.0"
                sourceId       = $workspaceResourceId
                category       = "sentinel"
            }
            tags = @{
                "hidden-sentinelWorkspaceId"  = $workspaceResourceId
                "hidden-sentinelContentType"  = "Workbook"
            }
        }

        $workbookPayload = $workbookBody | ConvertTo-Json -Depth 50 -EnumsAsStrings

        # Deploy workbook via Invoke-AzRestMethod (direct resource creation, not ARM deployment)
        $workbookPath = "/subscriptions/$($script:SubscriptionId)/resourceGroups/$ResourceGroup/providers/Microsoft.Insights/workbooks/${guid}?api-version=2022-04-01"

        try {
            $workbookResult = Invoke-AzRestMethod -Path $workbookPath -Method PUT -Payload $workbookPayload

            if ($workbookResult.StatusCode -in 200, 201) {
                if ($needsUpdate) {
                    Write-PipelineMessage "  Updated workbook: $displayName" -Level Success
                    $counters.Updated++
                }
                else {
                    Write-PipelineMessage "  Deployed workbook: $displayName" -Level Success
                    $counters.Deployed++
                }

                # Create metadata to link workbook back to solution
                $workbookResourceId = "/subscriptions/$($script:SubscriptionId)/resourceGroups/$ResourceGroup/providers/Microsoft.Insights/workbooks/$guid"
                $wbPackageId = if ($template.properties.PSObject.Properties.Name -contains "packageId") { $template.properties.packageId } else { $null }

                # Resolve solution display name and contentId for the metadata source block
                $wbSolEntry = if ($wbPackageId) {
                    $AvailableSolutions | Where-Object {
                        (($_.properties.PSObject.Properties.Name -contains "contentId") -and ($_.properties.contentId -eq $wbPackageId)) -or
                        ($_.name -eq $wbPackageId)
                    } | Select-Object -First 1
                }
                else { $null }

                $wbSolDisplayName = if ($wbSolEntry -and ($wbSolEntry.properties.PSObject.Properties.Name -contains "displayName")) { $wbSolEntry.properties.displayName } else { "Unknown" }
                $wbSolContentId   = if ($wbSolEntry -and ($wbSolEntry.properties.PSObject.Properties.Name -contains "contentId")) { $wbSolEntry.properties.contentId } else { $wbPackageId }

                $metadataBody = @{
                    properties = @{
                        contentId = $contentId
                        parentId  = $workbookResourceId
                        kind      = "Workbook"
                        version   = $templateVersion
                        source    = @{
                            kind     = "Solution"
                            name     = $wbSolDisplayName
                            sourceId = $wbSolContentId
                        }
                    }
                }

                $metadataPayload = $metadataBody | ConvertTo-Json -Depth 10 -Compress
                $metadataPath = "$($script:BaseUri)/providers/Microsoft.SecurityInsights/metadata/workbook-${guid}?api-version=$($script:MetadataApiVersion)"
                $metadataPath = $metadataPath.Replace($script:ServerUrl, "")

                $metadataResult = Invoke-AzRestMethod -Path $metadataPath -Method PUT -Payload $metadataPayload

                if ($metadataResult.StatusCode -notin 200, 201) {
                    Write-PipelineMessage "  Workbook deployed but metadata failed: $displayName (HTTP $($metadataResult.StatusCode))" -Level Warning
                }
            }
            else {
                Write-PipelineMessage "  Failed to deploy workbook: $displayName - HTTP $($workbookResult.StatusCode): $($workbookResult.Content)" -Level Error
                $counters.Failed++
            }
        }
        catch {
            Write-PipelineMessage "  Failed to deploy workbook: $displayName - $($_.Exception.Message)" -Level Error
            $counters.Failed++
        }

        Start-Sleep -Milliseconds 500
    }

    return $counters
}

# ---------------------------------------------------------------------------
# Automation Rule Reporting (deployed as part of the solution package)
# ---------------------------------------------------------------------------
function Get-AutomationRuleStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$SolutionNames
        ,
        [Parameter(Mandatory = $true)]
        [array]$AvailableSolutions
    )

    Write-PipelineMessage "Checking Automation Rule status..." -Level Section

    $templatesUrl = "$($script:BaseUri)/providers/Microsoft.SecurityInsights/contentTemplates?api-version=$($script:SentinelApiVersion)&`$filter=(properties/contentKind eq 'AutomationRule')"
    try {
        $templatesResult = Invoke-SentinelApi -Uri $templatesUrl -Method Get -Headers $script:AuthHeader
        $allTemplates = @(if ($templatesResult.PSObject.Properties.Name -contains "value") { $templatesResult.value } else { @() })
    }
    catch {
        Write-PipelineMessage "  No Automation Rule templates found." -Level Info
        return @{ Deployed = 0; Updated = 0; Skipped = 0; Failed = 0 }
    }

    $SolutionNamesLower = @($SolutionNames | ForEach-Object { $_.ToLower() })
    $solutionIdLookup = @{}
    foreach ($sol in $AvailableSolutions) {
        $solName = if ($sol.properties.PSObject.Properties.Name -contains "displayName") { $sol.properties.displayName } else { $null }
        if ($solName -and $SolutionNamesLower -contains $solName.ToLower()) {
            if (($sol.properties.PSObject.Properties.Name -contains "contentId") -and $sol.properties.contentId) {
                $solutionIdLookup[$sol.properties.contentId] = $solName
            }
            if ($sol.name) { $solutionIdLookup[$sol.name] = $solName }
        }
    }

    $targetTemplates = @($allTemplates | Where-Object {
        ($_.properties.PSObject.Properties.Name -contains "packageId") -and
        $solutionIdLookup.ContainsKey($_.properties.packageId)
    })

    $count = $targetTemplates.Count
    Write-PipelineMessage "  $count automation rule template(s) available from deployed solutions." -Level Info
    return @{ Deployed = $count; Updated = 0; Skipped = 0; Failed = 0 }
}

# ---------------------------------------------------------------------------
# Hunting Query Reporting (deployed as part of the solution package)
# ---------------------------------------------------------------------------
function Get-HuntingQueryStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$SolutionNames
        ,
        [Parameter(Mandatory = $true)]
        [array]$AvailableSolutions
    )

    Write-PipelineMessage "Checking Hunting Query status..." -Level Section

    $templatesUrl = "$($script:BaseUri)/providers/Microsoft.SecurityInsights/contentTemplates?api-version=$($script:SentinelApiVersion)&`$filter=(properties/contentKind eq 'HuntingQuery')"
    try {
        $templatesResult = Invoke-SentinelApi -Uri $templatesUrl -Method Get -Headers $script:AuthHeader
        $allTemplates = @(if ($templatesResult.PSObject.Properties.Name -contains "value") { $templatesResult.value } else { @() })
    }
    catch {
        Write-PipelineMessage "  No Hunting Query templates found." -Level Info
        return @{ Deployed = 0; Updated = 0; Skipped = 0; Failed = 0 }
    }

    $SolutionNamesLower = @($SolutionNames | ForEach-Object { $_.ToLower() })
    $solutionIdLookup = @{}
    foreach ($sol in $AvailableSolutions) {
        $solName = if ($sol.properties.PSObject.Properties.Name -contains "displayName") { $sol.properties.displayName } else { $null }
        if ($solName -and $SolutionNamesLower -contains $solName.ToLower()) {
            if (($sol.properties.PSObject.Properties.Name -contains "contentId") -and $sol.properties.contentId) {
                $solutionIdLookup[$sol.properties.contentId] = $solName
            }
            if ($sol.name) { $solutionIdLookup[$sol.name] = $solName }
        }
    }

    $targetTemplates = @($allTemplates | Where-Object {
        ($_.properties.PSObject.Properties.Name -contains "packageId") -and
        $solutionIdLookup.ContainsKey($_.properties.packageId)
    })

    $count = $targetTemplates.Count
    Write-PipelineMessage "  $count hunting query template(s) available from deployed solutions." -Level Info
    return @{ Deployed = $count; Updated = 0; Skipped = 0; Failed = 0 }
}

# ---------------------------------------------------------------------------
# Update Check (Standalone)
# ---------------------------------------------------------------------------
function Get-SolutionUpdateReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$SolutionStatuses
    )

    Write-PipelineMessage "Solution Update Report" -Level Section
    Write-PipelineMessage ("-" * 90) -Level Info

    $header = "{0,-45} {1,-15} {2,-15} {3,-12}" -f "Solution", "Installed", "Available", "Status"
    Write-PipelineMessage $header -Level Info
    Write-PipelineMessage ("-" * 90) -Level Info

    foreach ($status in $SolutionStatuses) {
        $installed = if ($status.InstalledVersion) { $status.InstalledVersion } else { "Not Installed" }
        $available = if ($status.AvailableVersion) { $status.AvailableVersion } else { "N/A" }

        $statusText = switch ($status.Status) {
            "Installed"       { "Current" }
            "UpdateAvailable" { "UPDATE" }
            "NotInstalled"    { "NEW" }
            "NotFound"        { "NOT FOUND" }
            default           { $status.Status }
        }

        $line = "{0,-45} {1,-15} {2,-15} {3,-12}" -f $status.Name, $installed, $available, $statusText
        $level = switch ($status.Status) {
            "UpdateAvailable" { "Warning" }
            "NotInstalled"    { "Info" }
            "NotFound"        { "Error" }
            default           { "Info" }
        }

        Write-PipelineMessage $line -Level $level
    }

    Write-PipelineMessage ("-" * 90) -Level Info
}

# ---------------------------------------------------------------------------
# Main Execution
# ---------------------------------------------------------------------------
function Main {
    [CmdletBinding()]
    param()

    $scriptStartTime = Get-Date

    # Handle comma-separated string input (from pipeline variable groups or CLI)
    if ($Solutions.Count -eq 1 -and $Solutions[0] -match ',') {
        $Solutions = $Solutions[0] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    }

    # Metadata tracking counters
    $script:MetadataLinked = 0
    $script:MetadataFailed = 0

    Write-PipelineMessage "================================================================" -Level Section
    Write-PipelineMessage "  Microsoft Sentinel Content Hub Deployment" -Level Section
    Write-PipelineMessage "  API Version: $($script:SentinelApiVersion) (GA)" -Level Info
    Write-PipelineMessage "  Script Version: 2.0.0" -Level Info
    Write-PipelineMessage "================================================================" -Level Section

    if ($WhatIf) {
        Write-PipelineMessage "*** DRY RUN MODE - No changes will be made ***" -Level Warning
    }

    # Display configuration
    Write-PipelineMessage "Configuration:" -Level Info
    Write-PipelineMessage "  Solutions:          $($Solutions -join ', ')" -Level Info
    Write-PipelineMessage "  Severities:         $($SeveritiesToInclude -join ', ')" -Level Info
    Write-PipelineMessage "  Disable Rules:      $DisableRules" -Level Info
    Write-PipelineMessage "  Protect Customised: $ProtectCustomisedRules" -Level Info
    Write-PipelineMessage "  Skip Analytics:     $SkipAnalyticsRules" -Level Info
    Write-PipelineMessage "  Skip Workbooks:     $SkipWorkbooks" -Level Info
    Write-PipelineMessage "  Skip Automation:    $SkipAutomationRules" -Level Info
    Write-PipelineMessage "  Skip Hunting:       $SkipHuntingQueries" -Level Info

    # Authenticate
    Connect-AzureEnvironment

    # Discover solutions
    $hubData = Get-ContentHubSolutions

    # Assess each requested solution
    $solutionStatuses = @()
    foreach ($solName in $Solutions) {
        $status = Get-SolutionStatus `
            -SolutionName $solName `
            -AvailableSolutions $hubData.Available `
            -InstalledLookup $hubData.InstalledLookup

        $solutionStatuses += $status
    }

    # Print update report
    Get-SolutionUpdateReport -SolutionStatuses $solutionStatuses

    # Track overall results
    $overallResults = @{
        Solutions       = @{ Deployed = 0; Updated = 0; Skipped = 0; Failed = 0 }
        AnalyticsRules  = @{ Deployed = 0; Updated = 0; Skipped = 0; CustomisedSkipped = 0; Failed = 0 }
        Workbooks       = @{ Deployed = 0; Updated = 0; Skipped = 0; Failed = 0 }
        AutomationRules = @{ Deployed = 0; Updated = 0; Skipped = 0; Failed = 0 }
        HuntingQueries  = @{ Deployed = 0; Skipped = 0; Failed = 0 }
    }

    # -----------------------------------------------------------------
    # Phase 1: Deploy/Update Solutions
    # -----------------------------------------------------------------
    if (-not $SkipSolutionDeployment) {
        Write-PipelineMessage "Phase 1: Solution Deployment" -Level Section

        foreach ($status in $solutionStatuses) {
            if ($status.Status -eq "NotFound") {
                $overallResults.Solutions.Failed++
                continue
            }

            $success = Deploy-Solution -SolutionStatus $status

            switch ($status.Action) {
                "Install"     { if ($success) { $overallResults.Solutions.Deployed++ } else { $overallResults.Solutions.Failed++ } }
                "Update"      { if ($success) { $overallResults.Solutions.Updated++ } else { $overallResults.Solutions.Failed++ } }
                "ForceUpdate" { if ($success) { $overallResults.Solutions.Updated++ } else { $overallResults.Solutions.Failed++ } }
                "None"        { $overallResults.Solutions.Skipped++ }
            }
        }
    }
    else {
        Write-PipelineMessage "Skipping solution deployment (SkipSolutionDeployment specified)." -Level Info
    }

    # Track which solutions were freshly installed or updated this run
    $script:NewlyDeployedSolutions = @($solutionStatuses | Where-Object {
        $_.Action -in @("Install", "Update", "ForceUpdate")
    } | ForEach-Object { $_.Name })

    if ($script:NewlyDeployedSolutions.Count -gt 0) {
        Write-PipelineMessage "Freshly deployed solutions (content will be force-processed): $($script:NewlyDeployedSolutions -join ', ')" -Level Info
    }

    # Determine which solutions to deploy content for
    $contentSolutionNames = @($solutionStatuses | Where-Object {
        $_.Status -ne "NotFound"
    } | ForEach-Object { $_.Name })

    if ($contentSolutionNames.Count -eq 0) {
        Write-PipelineMessage "No valid solutions found. Skipping content deployment." -Level Warning
    }
    else {
        # -----------------------------------------------------------------
        # Phase 2: Deploy Analytics Rules
        # -----------------------------------------------------------------
        if (-not $SkipAnalyticsRules) {
            $ruleCounters = Deploy-AnalyticsRules `
                -SolutionNames $contentSolutionNames `
                -AvailableSolutions $hubData.Available

            $overallResults.AnalyticsRules = $ruleCounters
        }
        else {
            Write-PipelineMessage "Skipping Analytics Rule deployment (SkipAnalyticsRules specified)." -Level Info
        }

        # -----------------------------------------------------------------
        # Phase 3: Workbook Status (deployed via solution package)
        # -----------------------------------------------------------------
        if (-not $SkipWorkbooks) {
            $wbCounters = Deploy-Workbooks `
                -SolutionNames $contentSolutionNames `
                -AvailableSolutions $hubData.Available

            $overallResults.Workbooks = $wbCounters
        }
        else {
            Write-PipelineMessage "Skipping Workbook check (SkipWorkbooks specified)." -Level Info
        }

        # -----------------------------------------------------------------
        # Phase 4: Automation Rule Status (deployed via solution package)
        # -----------------------------------------------------------------
        if (-not $SkipAutomationRules) {
            $arCounters = Get-AutomationRuleStatus `
                -SolutionNames $contentSolutionNames `
                -AvailableSolutions $hubData.Available

            $overallResults.AutomationRules = $arCounters
        }
        else {
            Write-PipelineMessage "Skipping Automation Rule check (SkipAutomationRules specified)." -Level Info
        }

        # -----------------------------------------------------------------
        # Phase 5: Hunting Query Status (deployed via solution package)
        # -----------------------------------------------------------------
        if (-not $SkipHuntingQueries) {
            $hqCounters = Get-HuntingQueryStatus `
                -SolutionNames $contentSolutionNames `
                -AvailableSolutions $hubData.Available

            $overallResults.HuntingQueries = $hqCounters
        }
        else {
            Write-PipelineMessage "Skipping Hunting Query check (SkipHuntingQueries specified)." -Level Info
        }
    }

    # -----------------------------------------------------------------
    # Final Summary
    # -----------------------------------------------------------------
    $scriptDuration = (Get-Date) - $scriptStartTime

    Write-PipelineMessage "" -Level Info
    Write-PipelineMessage "================================================================" -Level Section
    Write-PipelineMessage "  Deployment Summary" -Level Section
    Write-PipelineMessage "================================================================" -Level Section
    Write-PipelineMessage "" -Level Info
    Write-PipelineMessage "  Solutions:" -Level Info
    Write-PipelineMessage "    Deployed: $($overallResults.Solutions.Deployed)  Updated: $($overallResults.Solutions.Updated)  Skipped: $($overallResults.Solutions.Skipped)  Failed: $($overallResults.Solutions.Failed)" -Level Info
    Write-PipelineMessage "" -Level Info
    Write-PipelineMessage "  Analytics Rules:" -Level Info
    Write-PipelineMessage "    Deployed: $($overallResults.AnalyticsRules.Deployed)  Updated: $($overallResults.AnalyticsRules.Updated)  Skipped: $($overallResults.AnalyticsRules.Skipped)  Failed: $($overallResults.AnalyticsRules.Failed)" -Level Info
    if ($overallResults.AnalyticsRules.CustomisedSkipped -gt 0) {
        Write-PipelineMessage "    Customised rules protected: $($overallResults.AnalyticsRules.CustomisedSkipped)" -Level Warning
    }
    Write-PipelineMessage "" -Level Info
    Write-PipelineMessage "  Workbooks:" -Level Info
    Write-PipelineMessage "    Deployed: $($overallResults.Workbooks.Deployed)  Updated: $($overallResults.Workbooks.Updated)  Skipped: $($overallResults.Workbooks.Skipped)  Failed: $($overallResults.Workbooks.Failed)" -Level Info
    Write-PipelineMessage "" -Level Info
    Write-PipelineMessage "  Automation Rules:" -Level Info
    Write-PipelineMessage "    Deployed: $($overallResults.AutomationRules.Deployed)  Updated: $($overallResults.AutomationRules.Updated)  Skipped: $($overallResults.AutomationRules.Skipped)  Failed: $($overallResults.AutomationRules.Failed)" -Level Info
    Write-PipelineMessage "" -Level Info
    Write-PipelineMessage "  Hunting Queries:" -Level Info
    Write-PipelineMessage "    Deployed: $($overallResults.HuntingQueries.Deployed)  Skipped: $($overallResults.HuntingQueries.Skipped)  Failed: $($overallResults.HuntingQueries.Failed)" -Level Info
    Write-PipelineMessage "" -Level Info
    Write-PipelineMessage "  Metadata:" -Level Info
    Write-PipelineMessage "    Linked: $($script:MetadataLinked)  Failed: $($script:MetadataFailed)" -Level Info
    Write-PipelineMessage "" -Level Info
    Write-PipelineMessage "  Duration: $($scriptDuration.ToString('hh\:mm\:ss'))" -Level Info
    Write-PipelineMessage "================================================================" -Level Section

    # Set ADO pipeline variable for downstream tasks
    $totalFailed = $overallResults.Solutions.Failed + $overallResults.AnalyticsRules.Failed + $overallResults.Workbooks.Failed + $overallResults.AutomationRules.Failed + $overallResults.HuntingQueries.Failed

    if ($env:BUILD_BUILDID) {
        Write-Host "##vso[task.setvariable variable=SentinelDeploymentFailed]$totalFailed"
        Write-Host "##vso[task.setvariable variable=SentinelCustomisedRulesSkipped]$($overallResults.AnalyticsRules.CustomisedSkipped)"
    }

    if ($totalFailed -gt 0) {
        Write-PipelineMessage "Deployment completed with $totalFailed failure(s)." -Level Error
        if ($env:BUILD_BUILDID) {
            Write-Host "##vso[task.complete result=SucceededWithIssues;]Deployment completed with failures."
        }
        exit 1
    }
    else {
        Write-PipelineMessage "Deployment completed successfully." -Level Success
    }
}

# Execute
Main
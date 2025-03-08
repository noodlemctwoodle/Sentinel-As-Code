<#
.SYNOPSIS
    Deploys Microsoft Sentinel Solutions, Analytics Rules, and Workbooks to a specified Microsoft Sentinel workspace.
    
.DESCRIPTION
    This PowerShell script automates the deployment of Microsoft Sentinel solutions, analytics rules,
    and workbooks from the Content Hub into an Azure Sentinel workspace. It provides granular control
    over which resources to deploy, update, or skip. The script uses a unified resource testing framework
    to ensure consistent status checking across all resource types.
    
.PARAMETER ResourceGroup
    The name of the Azure Resource Group where the Sentinel workspace is located.
    
.PARAMETER Workspace
    The name of the Sentinel (Log Analytics) workspace.
    
.PARAMETER Region
    The Azure region where the workspace is deployed.
    
.PARAMETER Solutions
    An array of Microsoft Sentinel solutions to deploy.
    
.PARAMETER SeveritiesToInclude
    An optional list of rule severities to include (e.g., High, Medium, Low).
    
.PARAMETER IsGov
    Specifies whether the script should target an Azure Government cloud.
    
.PARAMETER ForceSolutionUpdate
    When specified, forces update of already installed solutions even if they're current.
    
.PARAMETER ForceRuleDeployment
    When specified, deploys rules for already installed solutions, not just newly deployed ones.
    
.PARAMETER SkipSolutionUpdates
    When specified, skips updating solutions that need updates.
    
.PARAMETER SkipRuleUpdates
    When specified, skips updating analytics rules that need updates.
    
.PARAMETER SkipRuleDeployment
    When specified, skips deploying analytics rules entirely.
    
.PARAMETER SkipWorkbookDeployment
    When specified, skips deploying workbooks entirely.
    
.PARAMETER ForceWorkbookDeployment
    When specified, forces redeployment of existing workbooks.
    
.NOTES
    Author: noodlemctwoodle
    Version: 1.0.0
    Last Updated: 08/03/2025
    GitHub Repository: Sentinel-As-Code
    
.EXAMPLE
    .\Set-SentinelContent.ps1 -ResourceGroup "Security-RG" -Workspace "MySentinelWorkspace" -Region "East US" -Solutions "Microsoft Defender XDR", "Microsoft 365" -SeveritiesToInclude "High", "Medium"
    Deploys "Microsoft Defender XDR" and "Microsoft 365" Sentinel solutions while filtering analytics rules to include only "High" and "Medium" severity incidents.
    
.EXAMPLE
    .\Set-SentinelContent.ps1 -ResourceGroup "Security-RG" -Workspace "MySentinelWorkspace" -Region "East US" -Solutions "Microsoft Defender XDR", "Microsoft 365" -SeveritiesToInclude "High", "Medium" -IsGov $true
    Deploys "Microsoft Defender XDR" and "Microsoft 365" Sentinel solutions while filtering analytics rules to include only "High" and "Medium" severity incidents in an Azure Government cloud environment.
    
.EXAMPLE
    .\Set-SentinelContent.ps1 -ResourceGroup "Security-RG" -Workspace "MySentinelWorkspace" -Region "East US" -Solutions "Microsoft 365", "Threat Intelligence" -ForceSolutionUpdate -SkipRuleUpdates
    Deploys solutions and forces update of already installed solutions, while skipping any rule updates.
#>

param(
    [Parameter(Mandatory = $true)][string]$ResourceGroup,                      # Azure Resource Group containing the Sentinel workspace
    [Parameter(Mandatory = $true)][string]$Workspace,                          # Microsoft Sentinel workspace name
    [Parameter(Mandatory = $true)][string]$Region,                             # Azure region (location) for deployments
    [Parameter(Mandatory = $true)][string[]]$Solutions,                        # Array of solution names to deploy
    [Parameter(Mandatory = $false)][string[]]$SeveritiesToInclude = @("High", "Medium", "Low"),  # Analytical rule severities to include
    [Parameter(Mandatory = $false)][string]$IsGov = "false",                   # Set to 'true' for Azure Government cloud
    [Parameter(Mandatory = $false)][switch]$ForceSolutionUpdate,               # Force update of already installed solutions
    [Parameter(Mandatory = $false)][switch]$ForceRuleDeployment,               # Force deployment of rules for already installed solutions
    [Parameter(Mandatory = $false)][switch]$SkipSolutionUpdates,               # Skip updating solutions that need updates
    [Parameter(Mandatory = $false)][switch]$SkipRuleUpdates,                   # Skip updating analytical rules that need updates
    [Parameter(Mandatory = $false)][switch]$SkipRuleDeployment,                # Skip deploying analytical rules entirely
    [Parameter(Mandatory = $false)][switch]$SkipWorkbookDeployment,            # Skip deploying workbooks entirely
    [Parameter(Mandatory = $false)][switch]$ForceWorkbookDeployment            # Force redeployment of existing workbooks
)

# Convert the string value to Boolean (supports 'true', '1', 'false', '0')
$IsGov = ($IsGov -eq 'true' -or $IsGov -eq '1')

Write-Host "GovCloud Mode: $IsGov"

# Ensure parameters are always treated as arrays, even when a single value is provided
if ($Solutions -isnot [array]) { $Solutions = @($Solutions) }
if ($SeveritiesToInclude -isnot [array]) { $SeveritiesToInclude = @($SeveritiesToInclude) }

<#
.SYNOPSIS
    Authenticates with Azure using the current context or prompts for login.

.DESCRIPTION
    Checks if an Azure context already exists. If not, prompts for authentication,
    using the appropriate environment (Government or Public).

.OUTPUTS
    Returns the Azure context object containing subscription information.
#>

function Connect-ToAzure {
    # Retrieve the current Azure context
    $context = Get-AzContext
    
    # If no context exists, authenticate with Azure (for GovCloud if specified)
    if (!$context) {
        if ($IsGov -eq $true) {
            Connect-AzAccount -Environment AzureUSGovernment
        } else {
            Connect-AzAccount
        }
        $context = Get-AzContext
    }
    
    return $context
}

# Establish Azure authentication and retrieve subscription details
$context = Connect-ToAzure
$SubscriptionId = $context.Subscription.Id
Write-Host "Connected to Azure with Subscription: $SubscriptionId" -ForegroundColor Blue

# Select the appropriate API endpoint based on the environment
$serverUrl = if ($IsGov -eq $true) { 
    "https://management.usgovcloudapi.net"  # Azure Government API endpoint
} else { 
    "https://management.azure.com"          # Azure Public API endpoint
}

# Construct the base URI for Sentinel API calls
$baseUri = "$serverUrl/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$Workspace"

# Retrieve an authorization token for API requests
$instanceProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile
$profileClient = New-Object -TypeName Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient -ArgumentList ($instanceProfile)
$token = $profileClient.AcquireAccessToken($context.Subscription.TenantId)

# Create the authentication header required for REST API calls
$authHeader = @{
    'Content-Type'  = 'application/json' 
    'Authorization' = 'Bearer ' + $token.AccessToken 
}

<#
.SYNOPSIS
    Evaluates the status of Sentinel resources (Solutions, Rules, Workbooks).

.DESCRIPTION
    Provides a unified interface for checking the status of different Sentinel resource types,
    including whether they are installed, need updates, or require deployment.

.PARAMETER ResourceType
    The type of Sentinel resource to evaluate: 'Solution', 'AnalyticsRule', or 'Workbook'.

.PARAMETER Resource
    The resource object being evaluated.

.PARAMETER InstalledPackages
    For Solution resources - array of installed content packages used to determine installation status.

.PARAMETER ExistingRulesByTemplate
    For AnalyticsRule resources - hashtable of existing rules indexed by template name.

.PARAMETER ExistingRulesByName
    For AnalyticsRule resources - hashtable of existing rules indexed by display name.

.PARAMETER ExistingWorkbooks
    For Workbook resources - array of existing workbooks to compare against.

.OUTPUTS
    Returns a hashtable containing status information about the resource.
#>

function Test-SentinelResource {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('Solution', 'AnalyticsRule', 'Workbook')]
        [string]$ResourceType,
        
        # Common parameters
        [Parameter(Mandatory = $true)]
        [object]$Resource,
        
        # Solution-specific parameters
        [Parameter(Mandatory = $false)]
        [array]$InstalledPackages = @(),
        
        # AnalyticsRule-specific parameters
        [Parameter(Mandatory = $false)]
        [hashtable]$ExistingRulesByTemplate,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$ExistingRulesByName,
        
        # Workbook-specific parameters
        [Parameter(Mandatory = $false)]
        [array]$ExistingWorkbooks = @()
    )
    
    # Create a base result object with properties common to all resource types
    $result = @{
        ResourceType = $ResourceType
        Status = "Unknown"
        DisplayName = ""
        Reason = ""
    }
    
    # Process based on resource type
    switch ($ResourceType) {
        'Solution' {
            # Validate required parameters
            if ($null -eq $Resource) {
                throw "Solution parameter is required when ResourceType is 'Solution'"
            }
            
            # Extract solution display name and ID
            $result.DisplayName = if ($Resource.properties.PSObject.Properties.Name -contains "displayName") {
                $Resource.properties.displayName
            } else {
                $Resource.name
            }
            
            $result.SolutionId = $Resource.name
            
            # If no installed packages, solution can't be installed
            if ($null -eq $InstalledPackages -or $InstalledPackages.Count -eq 0) {
                $result.Status = "NotInstalled"
                $result.Reason = "No installed solutions found"
                return $result
            }
            
            # Check for matching installed packages by display name
            $matchingPackages = $InstalledPackages | Where-Object {
                $_.properties.displayName -eq $result.DisplayName
            }
            
            if ($matchingPackages.Count -gt 0) {
                # Solution is installed, check if update is available
                $installedPackage = $matchingPackages[0]
                
                # Compare versions if available on both objects
                if ($Resource.properties.PSObject.Properties.Name -contains "version" -and 
                    $installedPackage.properties.PSObject.Properties.Name -contains "version") {
                    
                    $availableVersion = $Resource.properties.version
                    $installedVersion = $installedPackage.properties.version
                    
                    if ($availableVersion -gt $installedVersion) {
                        $result.Status = "NeedsUpdate"
                        $result.AvailableVersion = $availableVersion
                        $result.InstalledVersion = $installedVersion
                        $result.InstalledPackage = $installedPackage
                        $result.Reason = "Newer version available"
                        return $result
                    }
                }
                
                $result.Status = "Installed"
                $result.InstalledPackage = $installedPackage
                $result.Reason = "Solution is installed and up to date"
                return $result
            }
            
            # Check for special indicators in the name (Preview/Deprecated)
            if ($result.DisplayName -match "\[Preview\]" -or $result.DisplayName -match "\[Deprecated\]") {
                $result.Status = "Special"
                $result.Reason = "Solution is marked as Preview or Deprecated"
                return $result
            }
            
            # Default case: solution is not installed
            $result.Status = "NotInstalled"
            $result.Reason = "Solution is not installed"
            return $result
        }
        
        'AnalyticsRule' {
            # Validate required parameters
            if ($null -eq $Resource) {
                throw "RuleTemplate parameter is required when ResourceType is 'AnalyticsRule'"
            }
            if ($null -eq $ExistingRulesByTemplate) {
                throw "ExistingRulesByTemplate parameter is required when ResourceType is 'AnalyticsRule'"
            }
            if ($null -eq $ExistingRulesByName) {
                throw "ExistingRulesByName parameter is required when ResourceType is 'AnalyticsRule'"
            }
            
            # Extract rule details from template
            $result.DisplayName = $Resource.properties.mainTemplate.resources.properties[0].displayName
            $result.TemplateName = $Resource.properties.mainTemplate.resources[0].name
            $result.TemplateVersion = $Resource.properties.mainTemplate.resources.properties[1].version
            $result.Severity = $Resource.properties.mainTemplate.resources.properties[0].severity
            
            # Check if rule is deprecated
            if ($result.DisplayName -match "\[Deprecated\]") {
                $result.Status = "Deprecated"
                $result.ExistingRule = $null
                $result.Reason = "Rule is marked as deprecated"
                return $result
            }
            
            # Check if rule already exists by template name
            if ($ExistingRulesByTemplate.ContainsKey($result.TemplateName)) {
                $existingRule = $ExistingRulesByTemplate[$result.TemplateName]
                $currentVersion = $existingRule.properties.templateVersion
                
                # Check if rule needs an update by comparing versions
                if ($currentVersion -ne $result.TemplateVersion) {
                    $result.Status = "NeedsUpdate"
                    $result.ExistingRule = $existingRule
                    $result.CurrentVersion = $currentVersion
                    $result.Reason = "Template version is newer than deployed version"
                    return $result
                } else {
                    $result.Status = "Current"
                    $result.ExistingRule = $existingRule
                    $result.Reason = "Rule exists with current template version"
                    return $result
                }
            }
            # If not found by template name, check by display name
            elseif ($ExistingRulesByName.ContainsKey($result.DisplayName)) {
                $result.Status = "NameMatch"
                $result.ExistingRule = $ExistingRulesByName[$result.DisplayName]
                $result.Reason = "Rule with same name exists but not linked to template"
                return $result
            }
            # Rule doesn't exist and needs to be deployed
            else {
                $result.Status = "Missing"
                $result.ExistingRule = $null
                $result.Reason = "Rule does not exist and needs to be deployed"
                return $result
            }
        }
        
        'Workbook' {
            # Validate required parameters
            if ($null -eq $Resource) {
                throw "WorkbookTemplate parameter is required when ResourceType is 'Workbook'"
            }
            
            # Extract workbook details
            $result.DisplayName = $Resource.properties.displayName
            $result.TemplateId = $Resource.properties.contentId
            $result.TemplateVersion = $Resource.properties.version
            
            # Check if workbook is deprecated or in preview
            if ($result.DisplayName -match "\[Deprecated\]") {
                $result.Status = "Deprecated"
                $result.ExistingWorkbook = $null
                $result.Reason = "Workbook is marked as deprecated"
                return $result
            }
            
            if ($result.DisplayName -match "\[Preview\]") {
                $result.Status = "Preview"
                $result.Reason = "Workbook is marked as preview"
            }
            
            # Check if workbook already exists
            $existingWorkbook = $ExistingWorkbooks | Where-Object {
                $_.properties.contentId -eq $result.TemplateId
            } | Select-Object -First 1
            
            if ($existingWorkbook) {
                $result.ExistingWorkbook = $existingWorkbook
                $currentVersion = $existingWorkbook.properties.version
                
                # Check if version needs update
                if ($currentVersion -ne $result.TemplateVersion) {
                    $result.Status = "NeedsUpdate"
                    $result.CurrentVersion = $currentVersion
                    $result.Reason = "Template version is newer than deployed version"
                    return $result
                } else {
                    $result.Status = if ($result.Status -eq "Preview") { "PreviewCurrent" } else { "Current" }
                    $result.Reason = "Workbook exists with current template version"
                    return $result
                }
            }
            
            # Check if workbook with same name exists
            $nameMatch = $ExistingWorkbooks | Where-Object {
                $_.properties.displayName -eq $result.DisplayName
            } | Select-Object -First 1
            
            if ($nameMatch) {
                $result.Status = "NameMatch"
                $result.ExistingWorkbook = $nameMatch
                $result.Reason = "Workbook with same name exists but not linked to template"
                return $result
            }
            
            # Workbook doesn't exist
            $result.Status = if ($result.Status -eq "Preview") { "PreviewMissing" } else { "Missing" }
            $result.Reason = "Workbook does not exist and needs to be deployed"
            return $result
        }
    }
    
    # Should not reach here, but just in case
    $result.Status = "Unknown"
    $result.Reason = "Failed to determine status"
    return $result
}

<#
.SYNOPSIS
    Deploys Microsoft Sentinel solutions from the Content Hub.

.DESCRIPTION
    Fetches available Sentinel solutions from the Content Hub, checks their status,
    and deploys or updates solutions based on the specified parameters.

.PARAMETER ForceUpdate
    Forces update of solutions that are already installed, even if not required.

.PARAMETER SkipUpdates
    Skips updating solutions that need updates.

.OUTPUTS
    Returns a hashtable containing details of deployed, updated, installed, and failed solutions.
#>

function Deploy-Solutions {
    param(
        [Parameter(Mandatory = $false)][switch]$ForceUpdate,
        [Parameter(Mandatory = $false)][switch]$SkipUpdates
    )
    
    Write-Host "Fetching available Sentinel solutions..." -ForegroundColor Yellow
    $solutionURL = "$baseUri/providers/Microsoft.SecurityInsights/contentProductPackages?api-version=2024-03-01"

    try {
        $availableSolutions = (Invoke-RestMethod -Method "Get" -Uri $solutionURL -Headers $authHeader).value
        Write-Host "Successfully fetched $(($availableSolutions | Measure-Object).Count) Sentinel solutions." -ForegroundColor Green
    } catch {
        Write-Error "❌ ERROR: Failed to fetch Sentinel solutions: $($_.Exception.Message)"
        return @{ 
            Deployed = @()
            Updated = @()
            Installed = @()
            Failed = @()
        }
    }

    if ($null -eq $availableSolutions -or $availableSolutions.Count -eq 0) {
        Write-Error "❌ ERROR: No Sentinel solutions found! Exiting."
        return @{ 
            Deployed = @()
            Updated = @()
            Installed = @()
            Failed = @()
        }
    }
    
    # Get installed Content Packages to check solution status
    $contentPackagesUrl = "$baseUri/providers/Microsoft.SecurityInsights/contentPackages?api-version=2023-11-01"
    try {
        $result = Invoke-RestMethod -Method "Get" -Uri $contentPackagesUrl -Headers $authHeader
        $installedPackages = if ($result.PSObject.Properties.Name -contains "value") { $result.value } else { @() }
        
        Write-Host "Successfully fetched $(($installedPackages | Measure-Object).Count) installed solutions." -ForegroundColor Green
    } catch {
        Write-Warning "Failed to fetch installed solutions: $($_.Exception.Message). Assuming no solutions are installed."
        $installedPackages = @()
    }

    # Check each requested solution
    $solutionsToProcess = @()
    $skippedSolutions = @()
    $specialSolutions = @()
    
    foreach ($deploySolution in $Solutions) {
        # Find matching solution by name
        $matchingSolutions = $availableSolutions | Where-Object {
            $_.properties.displayName -eq $deploySolution
        }
        
        if ($matchingSolutions.Count -eq 0) {
            Write-Warning "⚠️ Solution '$deploySolution' not found in Content Hub. Skipping."
            continue
        }
        
        $singleSolution = $matchingSolutions[0]
        $solutionStatus = Test-SentinelResource -ResourceType Solution -Resource $singleSolution -InstalledPackages $installedPackages
        
        switch ($solutionStatus.Status) {
            "Installed" {
                if ($ForceUpdate) {
                    Write-Host "🔄 Solution '$($solutionStatus.DisplayName)' is installed but will be updated due to ForceUpdate." -ForegroundColor Cyan
                    $solutionsToProcess += [PSCustomObject]@{
                        Solution = $singleSolution
                        Status = $solutionStatus
                        Action = "Update"
                    }
                } else {
                    Write-Host "✅ Solution '$($solutionStatus.DisplayName)' is already installed." -ForegroundColor Green
                    $skippedSolutions += $solutionStatus
                }
            }
            "NeedsUpdate" {
                if ($SkipUpdates) {
                    Write-Host "⏭️ Solution '$($solutionStatus.DisplayName)' needs update but updates are being skipped." -ForegroundColor Yellow
                    $skippedSolutions += $solutionStatus
                } else {
                    Write-Host "🔄 Solution '$($solutionStatus.DisplayName)' needs update (v$($solutionStatus.InstalledVersion) → v$($solutionStatus.AvailableVersion))." -ForegroundColor Cyan
                    $solutionsToProcess += [PSCustomObject]@{
                        Solution = $singleSolution
                        Status = $solutionStatus
                        Action = "Update"
                    }
                }
            }
            "NotInstalled" {
                Write-Host "🚀 Solution '$($solutionStatus.DisplayName)' will be deployed." -ForegroundColor Yellow
                $solutionsToProcess += [PSCustomObject]@{
                    Solution = $singleSolution
                    Status = $solutionStatus
                    Action = "Install"
                }
            }
            "Special" {
                if ($ForceUpdate) {
                    Write-Host "🔄 Solution '$($solutionStatus.DisplayName)' is marked as special but will be deployed due to ForceUpdate." -ForegroundColor Cyan
                    $solutionsToProcess += [PSCustomObject]@{
                        Solution = $singleSolution
                        Status = $solutionStatus
                        Action = "Install"
                    }
                } else {
                    Write-Host "⚠️ Solution '$($solutionStatus.DisplayName)' is marked as special (preview or deprecated)." -ForegroundColor Yellow
                    $specialSolutions += $solutionStatus
                }
            }
        }
    }

    # Deploy or update solutions
    $deployedSolutions = @()
    $updatedSolutions = @()
    $failedSolutions = @()

    foreach ($solutionInfo in $solutionsToProcess) {
        $solution = $solutionInfo.Solution
        $status = $solutionInfo.Status
        $action = $solutionInfo.Action
        
        Write-Host "Processing $action for solution: $($status.DisplayName)" -ForegroundColor Cyan

        # Get detailed solution information
        $solutionURL = "$baseUri/providers/Microsoft.SecurityInsights/contentProductPackages/$($solution.name)?api-version=2024-03-01"

        try {
            $detailedSolution = (Invoke-RestMethod -Method "Get" -Uri $solutionURL -Headers $authHeader)
            if ($null -eq $detailedSolution) {
                Write-Warning "Failed to retrieve details for solution: $($status.DisplayName)"
                $failedSolutions += $status
                continue
            }
        } catch {
            Write-Error "Unable to retrieve solution details for $($status.DisplayName): $($_.Exception.Message)"
            $failedSolutions += $status
            continue
        }

        $packagedContent = $detailedSolution.properties.packagedContent

        # Ensure `api-version` is included in Content Templates requests
        foreach ($resource in $packagedContent.resources) { 
            if ($null -ne $resource.properties.mainTemplate.metadata.postDeployment) { 
                $resource.properties.mainTemplate.metadata.postDeployment = $null 
            } 
        }

        $installBody = @{
            "properties" = @{
                "parameters" = @{
                    "workspace"          = @{"value" = $Workspace }
                    "workspace-location" = @{"value" = $Region }
                }
                "template"   = $packagedContent
                "mode"       = "Incremental"
            }
        }

        $deploymentName = "allinone-$($solution.name)".Substring(0, [Math]::Min(64, ("allinone-$($solution.name)").Length))

        # Ensure `api-version` is correctly formatted in the URL
        $installURL = "$serverUrl/subscriptions/$SubscriptionId/resourcegroups/$ResourceGroup/providers/Microsoft.Resources/deployments/$deploymentName"
        $installURL = $installURL + "?api-version=2021-04-01"

        # Start deployment
        try {
            Write-Host "Starting deployment for $($status.DisplayName)..." -ForegroundColor Cyan
            
            # Convert the body to JSON, handling errors
            try {
                $jsonBody = $installBody | ConvertTo-Json -EnumsAsStrings -Depth 50 -EscapeHandling EscapeNonAscii
            } catch {
                Write-Error "❌ Failed to convert installation body to JSON: $($_.Exception.Message)"
                $failedSolutions += $status
                continue
            }
            
            # Log the URL for debugging
            Write-Verbose "Deployment URL: $installURL"
            
            $deploymentResult = Invoke-RestMethod -Uri $installURL -Method Put -Headers $authHeader -Body $jsonBody
            
            if ($null -eq $deploymentResult) {
                Write-Error "❌ Deployment returned null result for solution: $($status.DisplayName)"
                $failedSolutions += $status
                continue
            }
            
            Write-Host "✅ Deployment successful for solution: $($status.DisplayName)" -ForegroundColor Green
            
            if ($action -eq "Update") {
                $updatedSolutions += $status
            } else {
                $deployedSolutions += $status
            }
            
            # Increased delay to mitigate potential rate limiting
            Start-Sleep -Milliseconds 1000
        }
        catch {
            Write-Error "❌ Deployment failed for solution: $($status.DisplayName)"
            Write-Error "Azure API Error: $($_.Exception.Message)"
            
            # More detailed error information
            if ($_.Exception.Response) {
                $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                $responseBody = $reader.ReadToEnd()
                $reader.Close()
                Write-Error "Response status code: $($_.Exception.Response.StatusCode.value__)"
                Write-Error "Response body: $responseBody"
            }
            
            $failedSolutions += $status
        }
    }
    
    # Create a summary of what was done
    Write-Host "Solution Deployment Summary:" -ForegroundColor Blue
    Write-Host "  - Installed: $($deployedSolutions.Count)" -ForegroundColor Green
    Write-Host "  - Updated: $($updatedSolutions.Count)" -ForegroundColor Cyan
    Write-Host "  - Skipped: $($skippedSolutions.Count)" -ForegroundColor Yellow
    if ($specialSolutions.Count -gt 0) {
        Write-Host "  - Special (preview/deprecated): $($specialSolutions.Count)" -ForegroundColor Yellow
    }
    if ($failedSolutions.Count -gt 0) {
        Write-Host "  - Failed: $($failedSolutions.Count)" -ForegroundColor Red
    }
    
    # Return the combined list of all solutions that should have rules deployed
    return @{
        Deployed = $deployedSolutions | ForEach-Object { $_.DisplayName }
        Updated = $updatedSolutions | ForEach-Object { $_.DisplayName }
        Installed = $skippedSolutions | ForEach-Object { $_.DisplayName }
        Failed = $failedSolutions | ForEach-Object { $_.DisplayName }
    }
}

<#
.SYNOPSIS
    Deploys analytical rules for the specified Microsoft Sentinel solutions.

.DESCRIPTION
    Fetches analytical rule templates, filters them based on specified solutions and
    severities, and deploys or updates them as needed.

.PARAMETER DeployedSolutions
    Array of solution names to deploy analytical rules for. If empty, all available rules are considered.

.PARAMETER SkipTunedRulesText
    Text to identify rules that should be skipped (manually tuned/customized).

.PARAMETER SkipUpdates
    Skips updating rules that need updates.
#>

function Deploy-AnalyticalRules {
    param(
        [Parameter(Mandatory = $false)][string[]]$DeployedSolutions = @(),
        [Parameter(Mandatory = $false)][string]$SkipTunedRulesText = "",
        [Parameter(Mandatory = $false)][switch]$SkipUpdates
    )
    
    # Wait for solutions to finish deploying before deploying rules
    Write-Host "Waiting for solution deployment to complete..." -ForegroundColor Yellow
    Start-Sleep -Seconds 90  # Delay to ensure solutions are fully deployed before proceeding
    
    Write-Host "Fetching available Sentinel solutions..." -ForegroundColor Yellow
    $solutionURL = "$baseUri/providers/Microsoft.SecurityInsights/contentProductPackages?api-version=2024-03-01"

    try {
        $allSolutions = (Invoke-RestMethod -Method "Get" -Uri $solutionURL -Headers $authHeader).value
        Write-Host "✅ Successfully fetched Sentinel solutions." -ForegroundColor Green
    } catch {
        Write-Error "❌ ERROR: Failed to fetch Sentinel solutions: $($_.Exception.Message)"
        return
    }

    # Get all existing deployed Analytics Rules to check for duplicates and updates
    Write-Host "Fetching existing deployed Analytics Rules..." -ForegroundColor Yellow
    $existingRulesURL = "$baseUri/providers/Microsoft.SecurityInsights/alertRules?api-version=2022-12-01-preview"
    
    try {
        $existingRules = (Invoke-RestMethod -Uri $existingRulesURL -Method Get -Headers $authHeader).value
        Write-Host "✅ Successfully fetched $($existingRules.Count) existing deployed Analytics Rules." -ForegroundColor Green
    } catch {
        Write-Error "❌ ERROR: Failed to fetch existing deployed Analytics Rules: $($_.Exception.Message)"
        return
    }

    # Create lookup tables for existing rules by displayName and template name
    $existingRulesByName = @{}
    $existingRulesByTemplate = @{}
    
    foreach ($rule in $existingRules) {
        if ($rule.properties.displayName) {
            $existingRulesByName[$rule.properties.displayName] = $rule
        }
        
        if ($rule.properties.alertRuleTemplateName) {
            $existingRulesByTemplate[$rule.properties.alertRuleTemplateName] = $rule
        }
    }
    
    Write-Host "Fetching available Analytics Rule templates..." -ForegroundColor Yellow
    $ruleTemplateURL = "$baseUri/providers/Microsoft.SecurityInsights/contentTemplates?api-version=2023-05-01-preview"
    $ruleTemplateURL += "&%24filter=(properties%2FcontentKind%20eq%20'AnalyticsRule')"

    try {
        $ruleTemplates = (Invoke-RestMethod -Uri $ruleTemplateURL -Method Get -Headers $authHeader).value
        Write-Host "✅ Successfully fetched $($ruleTemplates.Count) available Analytics Rule templates." -ForegroundColor Green
    } catch {
        Write-Error "❌ ERROR: Failed to fetch Analytics Rule templates: $($_.Exception.Message)"
        return
    }

    if ($null -eq $ruleTemplates -or $ruleTemplates.Count -eq 0) {
        Write-Error "❌ ERROR: No Analytical Rule templates found! Exiting."
        return
    }

    # Filter rule templates to only include those from the specified solutions
    if ($DeployedSolutions.Count -gt 0) {
        Write-Host "Targeting rules for solutions: $($DeployedSolutions -join ', ')" -ForegroundColor Magenta
        
        # Find solutions that match the deployed solutions
        $relevantSolutions = $allSolutions | Where-Object { 
            $_.properties.displayName -in $DeployedSolutions 
        }
        
        # Extract solution IDs
        $deployedSolutionIds = @()
        foreach ($solution in $relevantSolutions) {
            if ($solution.properties.contentId) { $deployedSolutionIds += $solution.properties.contentId }
            if ($solution.properties.packageId) { $deployedSolutionIds += $solution.properties.packageId }
        }
        
        # Filter rule templates to only include those from the deployed solutions
        $rulesToProcess = $ruleTemplates | Where-Object { 
            $deployedSolutionIds -contains $_.properties.packageId 
        }
    } else {
        # If no solutions specified, use all templates
        $rulesToProcess = $ruleTemplates
    }
    
    Write-Host "Found $($rulesToProcess.Count) applicable Analytics Rule templates." -ForegroundColor Cyan
    
    if ($rulesToProcess.Count -eq 0) {
        Write-Warning "No rule templates found for the specified solutions."
        return
    }

    $BaseAlertUri = "$baseUri/providers/Microsoft.SecurityInsights/alertRules/"
    $BaseMetaURI = "$baseUri/providers/Microsoft.SecurityInsights/metadata/analyticsrule-"

    Write-Host "Severities to include: $($SeveritiesToInclude -join ', ')" -ForegroundColor Magenta

    # Counters for summary
    $deployedCount = 0
    $updatedCount = 0
    $skippedCount = 0
    $deprecatedCount = 0
    $failedCount = 0

    # Check each rule template using the Test-SentinelResource function
    $rulesToDeploy = @()
    
    foreach ($template in $rulesToProcess) {
        # Extract severity for filtering
        $severity = $template.properties.mainTemplate.resources.properties[0].severity
        
        # Check if rule matches severity filter
        if ($SeveritiesToInclude.Count -eq 0 -or $SeveritiesToInclude -contains $severity) {
            # Use the consolidated test function
            $ruleStatus = Test-SentinelResource -ResourceType AnalyticsRule -Resource $template -ExistingRulesByTemplate $existingRulesByTemplate -ExistingRulesByName $existingRulesByName
            
            switch ($ruleStatus.Status) {
                "Deprecated" {
                    Write-Host "⚠️ Skipping Deprecated Rule: $($ruleStatus.DisplayName)" -ForegroundColor Yellow
                    $deprecatedCount++
                    continue
                }
                "Current" {
                    Write-Host "⏭️ Skipping rule (already exists with current version): $($ruleStatus.DisplayName)" -ForegroundColor Yellow
                    $skippedCount++
                    continue
                }
                "NeedsUpdate" {
                    if ($SkipUpdates) {
                        Write-Host "⏭️ Skipping update for rule: $($ruleStatus.DisplayName) (current version: $($ruleStatus.CurrentVersion))" -ForegroundColor Yellow
                        $skippedCount++
                        continue
                    } else {
                        Write-Host "🔄 Updating existing rule: $($ruleStatus.DisplayName) (Version $($ruleStatus.CurrentVersion) → $($ruleStatus.TemplateVersion))" -ForegroundColor Cyan
                        $rulesToDeploy += [PSCustomObject]@{
                            Template = $template
                            DisplayName = $ruleStatus.DisplayName
                            Severity = $severity
                            TemplateName = $ruleStatus.TemplateName
                            TemplateVersion = $ruleStatus.TemplateVersion
                            ExistingRule = $ruleStatus.ExistingRule
                            NeedsUpdate = $true
                        }
                    }
                }
                "NameMatch" {
                    Write-Host "⏭️ Skipping rule (name match): $($ruleStatus.DisplayName)" -ForegroundColor Yellow
                    $skippedCount++
                    continue
                }
                "Missing" {
                    #Write-Host "🚀 Deploying new Analytics Rule: $($ruleStatus.DisplayName)" -ForegroundColor Cyan
                    $rulesToDeploy += [PSCustomObject]@{
                        Template = $template
                        DisplayName = $ruleStatus.DisplayName
                        Severity = $severity
                        TemplateName = $ruleStatus.TemplateName
                        TemplateVersion = $ruleStatus.TemplateVersion
                        ExistingRule = $null
                        NeedsUpdate = $false
                    }
                }
            }
        }
    }

    # Deploy or update rules
    foreach ($ruleToDeploy in $rulesToDeploy) {
        $template = $ruleToDeploy.Template
        $displayName = $ruleToDeploy.DisplayName
        $templateName = $ruleToDeploy.TemplateName
        $templateVersion = $ruleToDeploy.TemplateVersion
        $existingRule = $ruleToDeploy.ExistingRule
        $needsUpdate = $ruleToDeploy.NeedsUpdate
        
        # Prepare rule properties
        $kind = $template.properties.mainTemplate.resources[0].kind
        $properties = $template.properties.mainTemplate.resources[0].properties
        $properties.enabled = $true

        # Add linking fields
        $properties | Add-Member -NotePropertyName "alertRuleTemplateName" -NotePropertyValue $templateName -Force
        $properties | Add-Member -NotePropertyName "templateVersion" -NotePropertyValue $templateVersion -Force

        # If updating an existing rule, preserve custom entity mappings and details
        if ($needsUpdate -and $existingRule) {
            # Preserve custom entity mappings if they exist
            if ($existingRule.properties.PSObject.Properties.Name -contains "entityMappings") {
                Write-Host "   - Preserving custom entity mappings" -ForegroundColor Cyan
                $properties.entityMappings = $existingRule.properties.entityMappings
            }
            
            # Preserve custom details if they exist
            if ($existingRule.properties.PSObject.Properties.Name -contains "customDetails") {
                Write-Host "   - Preserving custom details" -ForegroundColor Cyan
                $properties | Add-Member -NotePropertyName "customDetails" -NotePropertyValue $existingRule.properties.customDetails -Force
            }
        }
        # Otherwise ensure entity mappings is an array
        elseif ($properties.PSObject.Properties.Name -contains "entityMappings") {
            if ($properties.entityMappings -isnot [System.Array]) {
                $properties.entityMappings = @($properties.entityMappings)
            }
        }

        # Ensure requiredDataConnectors is an object
        if ($properties.PSObject.Properties.Name -contains "requiredDataConnectors") {
            if ($properties.requiredDataConnectors -is [System.Array] -and $properties.requiredDataConnectors.Count -eq 1) {
                $properties.requiredDataConnectors = $properties.requiredDataConnectors[0]
            }
        }

        # Fix Grouping Configuration 
        if ($properties.PSObject.Properties.Name -contains "incidentConfiguration") {
            if ($properties.incidentConfiguration.PSObject.Properties.Name -contains "groupingConfiguration") {
                if (-not $properties.incidentConfiguration.groupingConfiguration) {
                    $properties.incidentConfiguration | Add-Member -NotePropertyName "groupingConfiguration" -NotePropertyValue @{
                        matchingMethod = "AllEntities"
                        lookbackDuration = "PT1H"
                    }
                } else {
                    # Ensure `matchingMethod` exists
                    if (-not ($properties.incidentConfiguration.groupingConfiguration.PSObject.Properties.Name -contains "matchingMethod")) {
                        $properties.incidentConfiguration.groupingConfiguration | Add-Member -NotePropertyName "matchingMethod" -NotePropertyValue "AllEntities"
                    }

                    # Ensure `lookbackDuration` is in ISO 8601 format
                    if ($properties.incidentConfiguration.groupingConfiguration.PSObject.Properties.Name -contains "lookbackDuration") {
                        $lookbackDuration = $properties.incidentConfiguration.groupingConfiguration.lookbackDuration
                        if ($lookbackDuration -match "^(\d+)(h|d|m)$") {
                            $timeValue = $matches[1]
                            $timeUnit = $matches[2]
                            switch ($timeUnit) {
                                "h" { $isoDuration = "PT${timeValue}H" }
                                "d" { $isoDuration = "P${timeValue}D" }
                                "m" { $isoDuration = "PT${timeValue}M" }
                            }
                            $properties.incidentConfiguration.groupingConfiguration.lookbackDuration = $isoDuration
                        }
                    }
                }
            }
        }

        # Create JSON body based on rule type
        $body = @{
            "kind"       = $kind
            "properties" = $properties
        }

        # For updates, use existing rule ID; for new rules, generate a GUID
        $ruleId = if ($needsUpdate) { $existingRule.name } else { (New-Guid).Guid }
        $alertUri = "$BaseAlertUri$ruleId" + "?api-version=2022-12-01-preview"

        try {
            $jsonBody = $body | ConvertTo-Json -Depth 50 -Compress
            $verdict = Invoke-RestMethod -Uri $alertUri -Method Put -Headers $authHeader -Body $jsonBody
            
            if ($needsUpdate) {
                Write-Host "✅ Successfully updated rule: $displayName" -ForegroundColor Green
                $updatedCount++
            } else {
                Write-Host "✅ Successfully deployed rule: $displayName" -ForegroundColor Green
                $deployedCount++
            }

            # Find the solution for this rule
            $solution = $allSolutions | Where-Object { 
                ($_.properties.contentId -eq $template.properties.packageId) -or 
                ($_.properties.packageId -eq $template.properties.packageId)
            } | Select-Object -First 1

            if ($solution) {
                $sourceName = $solution.properties.displayName
                $sourceId = $solution.name
            } else {
                $sourceName = "Unknown Solution"
                $sourceId = "Unknown-ID"
                Write-Warning "⚠️ No matching solution found for: $displayName"
            }

            # Create metadata
            $metaBody = @{
                "apiVersion" = "2022-01-01-preview"
                "name"       = "analyticsrule-" + $verdict.name
                "type"       = "Microsoft.OperationalInsights/workspaces/providers/metadata"
                "id"         = $null
                "properties" = @{
                    "contentId" = $templateName
                    "parentId"  = $verdict.id
                    "kind"      = "AnalyticsRule"
                    "version"   = $templateVersion
                    "source"    = @{
                        "kind"     = "Solution"
                        "name"     = $sourceName
                        "sourceId" = $sourceId
                    }
                }
            }

            # Send metadata update
            $metaUri = "$BaseMetaURI$($verdict.name)?api-version=2022-01-01-preview"
            Invoke-RestMethod -Uri $metaUri -Method Put -Headers $authHeader -Body ($metaBody | ConvertTo-Json -Depth 5 -Compress) | Out-Null

            # Update lookup tables with newly deployed/updated rule
            $existingRulesByName[$displayName] = $verdict
            $existingRulesByTemplate[$templateName] = $verdict

        } catch {
            if ($_.ErrorDetails.Message -match "One of the tables does not exist") {
                Write-Warning "⏭️ Skipping $displayName due to missing tables in the environment."
            } elseif ($_.ErrorDetails.Message -match "The given column") {
                Write-Warning "⏭️ Skipping $displayName due to missing column in the query."
            } elseif ($_.ErrorDetails.Message -match "FailedToResolveScalarExpression|SemanticError") {
                Write-Warning "⏭️ Skipping $displayName due to an invalid expression in the query."
            } else {
                Write-Error "❌ ERROR: Deployment failed for Analytical Rule: $displayName"
                Write-Error "Azure API Error: $($_.Exception.Message)"
            }
            $skippedCount++
        }
    }

    # Display summary
    Write-Host "Analytics Rules Deployment Summary:" -ForegroundColor Blue
    Write-Host "  - Installed: $deployedCount" -ForegroundColor Green
    Write-Host "  - Updated: $updatedCount" -ForegroundColor Cyan
    Write-Host "  - Skipped: $skippedCount" -ForegroundColor Yellow
    if ($deprecatedCount -gt 0) {
        Write-Host "  - Deprecated: $deprecatedCount" -ForegroundColor Yellow
    }
    if ($failedCount -gt 0) {
        Write-Host "  - Failed: $failedCount" -ForegroundColor Red
    }
}

# Function to deploy workbooks
<#
.SYNOPSIS
    Deploys Microsoft Sentinel workbooks for specified solutions.

.DESCRIPTION
    Fetches workbook templates from the Content Hub, filters them based on specified solutions,
    and deploys or updates them as needed.

.PARAMETER DeployedSolutions
    Array of solution names to deploy workbooks for. If empty, all available workbooks are considered.

.PARAMETER DeployExistingWorkbooks
    When specified, redeploys workbooks that are already installed with current versions.

.PARAMETER SkipUpdates
    Skips updating workbooks that need updates.
#>

function Deploy-SolutionWorkbooks {
    param(
        [Parameter(Mandatory = $false)][string[]]$DeployedSolutions = @(),
        [Parameter(Mandatory = $false)][switch]$DeployExistingWorkbooks, # Redeploy workbooks even if they exist
        [Parameter(Mandatory = $false)][switch]$SkipUpdates              # Skip updating workbooks that need updates
    )

    Write-Host "Deploying workbooks for installed solutions..." -ForegroundColor Yellow
    
    # Get all workbook templates from Content Hub
    Write-Host "Getting all workbook templates from Content Hub..." -ForegroundColor Cyan
    $workbookTemplateURL = "$baseUri/providers/Microsoft.SecurityInsights/contentTemplates?api-version=2023-05-01-preview"
    $workbookTemplateURL += "&%24filter=(properties%2FcontentKind%20eq%20'Workbook')"
    
    try {
        $workbookTemplates = (Invoke-RestMethod -Uri $workbookTemplateURL -Method Get -Headers $authHeader).value
        Write-Host "✅ Successfully fetched $($workbookTemplates.Count) workbook templates." -ForegroundColor Green
    } catch {
        Write-Error "❌ ERROR: Failed to fetch workbook templates: $($_.Exception.Message)"
        return
    }
    
    if ($null -eq $workbookTemplates -or $workbookTemplates.Count -eq 0) {
        Write-Warning "No workbook templates found in Content Hub."
        return
    }
    
    # Filter workbook templates to those from deployed solutions
    $relevantWorkbooks = @()
    
    if ($DeployedSolutions.Count -gt 0) {
        # Get all solutions to find workbooks related to deployed solutions
        $solutionURL = "$baseUri/providers/Microsoft.SecurityInsights/contentProductPackages?api-version=2024-03-01"
        
        try {
            $allSolutions = (Invoke-RestMethod -Method "Get" -Uri $solutionURL -Headers $authHeader).value
            
            # Find solutions that match the deployed solutions
            $relevantSolutions = $allSolutions | Where-Object { 
                $_.properties.displayName -in $DeployedSolutions 
            }
            
            # Extract solution IDs
            $deployedSolutionIds = @()
            foreach ($solution in $relevantSolutions) {
                if ($solution.properties.contentId) { $deployedSolutionIds += $solution.properties.contentId }
                if ($solution.properties.packageId) { $deployedSolutionIds += $solution.properties.packageId }
            }
            
            # Filter workbook templates to those from deployed solutions
            $relevantWorkbooks = $workbookTemplates | Where-Object {
                $deployedSolutionIds -contains $_.properties.packageId
            }
        } catch {
            Write-Error "❌ ERROR: Failed to fetch Sentinel solutions: $($_.Exception.Message)"
            return
        }
    } else {
        # If no specific solutions provided, use all templates
        $relevantWorkbooks = $workbookTemplates
    }
    
    Write-Host "Found $($relevantWorkbooks.Count) workbooks associated with deployed solutions." -ForegroundColor Cyan
    
    # Get existing workbooks to check which ones to skip
    Write-Host "Checking for existing workbooks..." -ForegroundColor Cyan
    $workbookMetadataURL = "$baseUri/providers/Microsoft.SecurityInsights/metadata?api-version=2023-05-01-preview"
    $workbookMetadataURL += "&%24filter=(properties%2FKind%20eq%20'Workbook')"
    
    try {
        $workbookMetadata = (Invoke-RestMethod -Uri $workbookMetadataURL -Method Get -Headers $authHeader).value
        Write-Host "✅ Successfully fetched metadata for $($workbookMetadata.Count) existing workbooks." -ForegroundColor Green
    } catch {
        Write-Warning "Failed to fetch workbook metadata: $($_.Exception.Message)"
        $workbookMetadata = @()
    }
    
    # Counters for tracking progress
    $deployedCount = 0
    $updatedCount = 0
    $skippedCount = 0
    $deprecatedCount = 0
    $failedCount = 0
    
    # Create a list of workbooks to deploy or update
    $workbooksToProcess = @()
    
    foreach ($workbookTemplate in $relevantWorkbooks) {
        # Use consolidated test function
        $workbookStatus = Test-SentinelResource -ResourceType Workbook -Resource $workbookTemplate -ExistingWorkbooks $workbookMetadata
        
        switch ($workbookStatus.Status) {
            { $_ -in "Current", "PreviewCurrent" } {
                if (-not $DeployExistingWorkbooks) {
                    Write-Host "⏭️ Skipping workbook (already exists with current version): $($workbookStatus.DisplayName)" -ForegroundColor Yellow
                    $skippedCount++
                    continue
                } else {
                    # Force redeploy even though current
                    $workbooksToProcess += [PSCustomObject]@{
                        Template = $workbookTemplate
                        DisplayName = $workbookStatus.DisplayName
                        ExistingWorkbook = $workbookStatus.ExistingWorkbook
                        Action = "Redeploy"
                    }
                }
            }
            "NeedsUpdate" {
                if ($SkipUpdates) {
                    Write-Host "⏭️ Skipping update for workbook: $($workbookStatus.DisplayName) (current version: $($workbookStatus.CurrentVersion))" -ForegroundColor Yellow
                    $skippedCount++
                    continue
                } else {
                    Write-Host "🔄 Workbook needs update: $($workbookStatus.DisplayName) (Version $($workbookStatus.CurrentVersion) → $($workbookStatus.TemplateVersion))" -ForegroundColor Cyan
                    $workbooksToProcess += [PSCustomObject]@{
                        Template = $workbookTemplate
                        DisplayName = $workbookStatus.DisplayName
                        ExistingWorkbook = $workbookStatus.ExistingWorkbook
                        Action = "Update"
                    }
                }
            }
            { $_ -in "Missing", "PreviewMissing" } {
                #Write-Host "🚀 New workbook to deploy: $($workbookStatus.DisplayName)" -ForegroundColor Cyan
                $workbooksToProcess += [PSCustomObject]@{
                    Template = $workbookTemplate
                    DisplayName = $workbookStatus.DisplayName
                    ExistingWorkbook = $null
                    Action = "Deploy"
                }
            }
            "Deprecated" {
                Write-Host "⚠️ Skipping deprecated workbook: $($workbookStatus.DisplayName)" -ForegroundColor Yellow
                $deprecatedCount++
                continue
            }
            "NameMatch" {
                Write-Host "⏭️ Skipping workbook (name match): $($workbookStatus.DisplayName)" -ForegroundColor Yellow
                $skippedCount++
                continue
            }
        }
    }
    
    # Process workbooks
    foreach ($workbookInfo in $workbooksToProcess) {
        $workbookTemplate = $workbookInfo.Template
        $displayName = $workbookInfo.DisplayName
        $existingWorkbook = $workbookInfo.ExistingWorkbook
        $action = $workbookInfo.Action
        
        # Get detailed workbook template
        $workbookDetailURL = "$baseUri/providers/Microsoft.SecurityInsights/contentTemplates/$($workbookTemplate.name)?api-version=2023-05-01-preview"
        
        try {
            $workbookDetail = (Invoke-RestMethod -Uri $workbookDetailURL -Method Get -Headers $authHeader).properties.mainTemplate.resources
            
            # Extract workbook and metadata resources
            $workbookResource = $workbookDetail | Where-Object type -eq 'Microsoft.Insights/workbooks'
            $metadataResource = $workbookDetail | Where-Object type -eq 'Microsoft.OperationalInsights/workspaces/providers/metadata'
            
            if (-not $workbookResource) {
                Write-Warning "Could not find workbook resource in template: $displayName"
                $failedCount++
                continue
            }
            
            # Generate new GUID for the workbook or use existing ID for updates
            $guid = if ($action -eq "Update" -and $existingWorkbook) {
                # Extract GUID from the parentId
                if ($existingWorkbook.properties.parentId -match '/([^/]+)$') {
                    $matches[1]
                } else {
                    # Fallback to new GUID if we can't extract it
                    (New-Guid).Guid
                }
            } else {
                (New-Guid).Guid
            }
            
            # Prepare workbook for deployment
            $newWorkbook = $workbookResource | Select-Object * -ExcludeProperty apiVersion, metadata, name
            $newWorkbook | Add-Member -NotePropertyName name -NotePropertyValue $guid
            $newWorkbook | Add-Member -NotePropertyName location -NotePropertyValue $Region -Force
            
            # Ensure required properties are present
            if (-not ($newWorkbook.PSObject.Properties.Name -contains "kind")) {
                $newWorkbook | Add-Member -NotePropertyName kind -NotePropertyValue "shared"
            }
            
            if (-not ($newWorkbook.PSObject.Properties.Name -contains "tags")) {
                $newWorkbook | Add-Member -NotePropertyName tags -NotePropertyValue @{
                    "hidden-title" = $displayName
                    "source" = "Microsoft Sentinel"
                }
            }
            
            $workbookPayload = $newWorkbook | ConvertTo-Json -Depth 50 -EnumsAsStrings
            
            # If updating, delete the old workbook first if it's a different ID
            if ($action -eq "Update" -and $existingWorkbook) {
                $oldMetadataName = $existingWorkbook.name
                $oldWorkbookName = $oldMetadataName -replace 'workbook-', ''
                
                if ($oldWorkbookName -ne $guid) {
                    # Delete old workbook
                    Write-Host "   - Deleting old workbook version" -ForegroundColor Cyan
                    $deleteWorkbookPath = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Insights/workbooks/$oldWorkbookName"
                    $deleteWorkbookPath += "?api-version=2022-04-01"
                    
                    $deleteResult = Invoke-AzRestMethod -Path $deleteWorkbookPath -Method DELETE
                    
                    # Check result of workbook deletion
                    if ($deleteResult.StatusCode -in 200, 201, 204) {
                        Write-Host "     ✅ Successfully deleted old workbook" -ForegroundColor Green
                    } 
                    elseif ($deleteResult.StatusCode -eq 404) {
                        Write-Host "     ⚠️ Old workbook not found (already deleted)" -ForegroundColor Yellow
                    }
                    else {
                        Write-Warning "     ⚠️ Failed to delete old workbook: Status $($deleteResult.StatusCode)"
                        Write-Verbose "Response: $($deleteResult.Content)"
                    }
                    
                    # Delete old metadata
                    $deleteMetadataPath = "$baseUri/providers/Microsoft.SecurityInsights/metadata/$oldMetadataName".Replace("https://management.azure.com", "")
                    $deleteMetadataPath += "?api-version=2023-05-01-preview"
                    
                    $deleteMetadataResult = Invoke-AzRestMethod -Path $deleteMetadataPath -Method DELETE
                    
                    # Check result of metadata deletion
                    if ($deleteMetadataResult.StatusCode -in 200, 201, 204) {
                        Write-Host "     ✅ Successfully deleted workbook metadata" -ForegroundColor Green
                    } 
                    elseif ($deleteMetadataResult.StatusCode -eq 404) {
                        Write-Host "     ⚠️ Old workbook metadata not found (already deleted)" -ForegroundColor Yellow
                    }
                    else {
                        Write-Warning "     ⚠️ Failed to delete workbook metadata: Status $($deleteMetadataResult.StatusCode)"
                        Write-Verbose "Response: $($deleteMetadataResult.Content)"
                    }
                }
            }
            
            # Create/update workbook using Invoke-AzRestMethod
            $workbookCreatePath = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Insights/workbooks/$guid"
            $workbookCreatePath += "?api-version=2022-04-01"
            
            $workbookResult = Invoke-AzRestMethod -Path $workbookCreatePath -Method PUT -Payload $workbookPayload
            
            if ($workbookResult.StatusCode -in 200, 201) {
                if ($action -eq "Update") {
                    Write-Host "✅ Successfully updated workbook: $displayName" -ForegroundColor Green
                    $updatedCount++
                } else {
                    Write-Host "✅ Successfully deployed workbook: $displayName" -ForegroundColor Green
                    $deployedCount++
                }
                
                # Create metadata
                if ($metadataResource) {
                    $metadataDeployment = $metadataResource | Select-Object * -ExcludeProperty apiVersion, name
                    $metadataDeployment | Add-Member -NotePropertyName name -NotePropertyValue "workbook-$guid" -Force
                    
                    # Update parent ID to point to the new workbook
                    $workbookParentId = $metadataDeployment.properties.parentId -replace '/[^/]+$', "/$guid"
                    $metadataDeployment.properties | Add-Member -NotePropertyName parentId -NotePropertyValue $workbookParentId -Force
                    
                    $metadataPayload = $metadataDeployment | ConvertTo-Json -Depth 50 -EnumsAsStrings
                    
                    $metadataPath = "$baseUri/providers/Microsoft.SecurityInsights/metadata/workbook-$guid".Replace("https://management.azure.com", "")
                    $metadataPath += "?api-version=2023-05-01-preview"
                    
                    $metadataResult = Invoke-AzRestMethod -Path $metadataPath -Method PUT -Payload $metadataPayload
                    
                    if (-not ($metadataResult.StatusCode -in 200, 201)) {
                        Write-Warning "⚠️ Workbook created but metadata update failed: $displayName"
                        Write-Warning "Status: $($metadataResult.StatusCode)"
                        Write-Warning "Response: $($metadataResult.Content)"
                    }
                }
            } else {
                Write-Error "❌ Failed to deploy workbook $displayName"
                Write-Error "Status: $($workbookResult.StatusCode)"
                Write-Error "Response: $($workbookResult.Content)"
                $failedCount++
            }
        } catch {
            Write-Error "❌ Failed to deploy workbook $displayName : $($_.Exception.Message)"
            $failedCount++
        }
    }
    
    # Display summary
    Write-Host "Workbook Deployment Summary:" -ForegroundColor Blue
    Write-Host "  - Installed: $deployedCount" -ForegroundColor Green
    Write-Host "  - Updated: $updatedCount" -ForegroundColor Cyan
    Write-Host "  - Skipped: $skippedCount" -ForegroundColor Yellow
    if ($deprecatedCount -gt 0) {
        Write-Host "  - Deprecated: $deprecatedCount" -ForegroundColor Yellow
    }
    if ($failedCount -gt 0) {
        Write-Host "  - Failed: $failedCount" -ForegroundColor Red
    }
}

# Main execution block

# First, deploy the requested solutions
$deploymentResults = Deploy-Solutions -ForceUpdate:$ForceSolutionUpdate -SkipUpdates:$SkipSolutionUpdates

# Skip analytical rule deployment if requested
if ($SkipRuleDeployment) {
    Write-Host "⏭️ Skipping analytical rules deployment as requested." -ForegroundColor Yellow
} else {
    # Determine which solutions to deploy rules for
    $solutionsForRules = @()

    # Add newly deployed solutions
    if ($deploymentResults.Deployed -and $deploymentResults.Deployed.Count -gt 0) {
        $solutionsForRules += $deploymentResults.Deployed
    }

    # Add updated solutions
    if ($deploymentResults.Updated -and $deploymentResults.Updated.Count -gt 0) {
        $solutionsForRules += $deploymentResults.Updated
    }

    # Add already installed solutions if ForceRuleDeployment is specified
    if ($ForceRuleDeployment -and $deploymentResults.Installed -and $deploymentResults.Installed.Count -gt 0) {
        $solutionsForRules += $deploymentResults.Installed
    }

    # Deploy analytical rules if we have applicable solutions
    if ($solutionsForRules.Count -gt 0) {
        Deploy-AnalyticalRules -DeployedSolutions $solutionsForRules -SkipUpdates:$SkipRuleUpdates
    } else {
        Write-Host "⏭️ No solutions deployed or updated. Skipping analytical rules deployment." -ForegroundColor Yellow
    }
}

# Handle workbook deployment
if ($SkipWorkbookDeployment) {
    Write-Host "Skipping workbook deployment as requested." -ForegroundColor Yellow
} else {
    # Determine which solutions to deploy workbooks for
    $solutionsForWorkbooks = @()
    
    # Add newly deployed solutions
    if ($deploymentResults.Deployed -and $deploymentResults.Deployed.Count -gt 0) {
        $solutionsForWorkbooks += $deploymentResults.Deployed
    }

    # Add updated solutions
    if ($deploymentResults.Updated -and $deploymentResults.Updated.Count -gt 0) {
        $solutionsForWorkbooks += $deploymentResults.Updated
    }

    # Add already installed solutions if ForceWorkbookDeployment is specified
    if ($ForceWorkbookDeployment -and $deploymentResults.Installed -and $deploymentResults.Installed.Count -gt 0) {
        $solutionsForWorkbooks += $deploymentResults.Installed
    }
    
    # Deploy workbooks if we have applicable solutions
    if ($solutionsForWorkbooks.Count -gt 0) {
        Deploy-SolutionWorkbooks -DeployedSolutions $solutionsForWorkbooks -SkipUpdates:$SkipSolutionUpdates -DeployExistingWorkbooks:$ForceWorkbookDeployment
    } else {
        Write-Host "⏭️ No solutions to deploy workbooks for. Skipping workbook deployment." -ForegroundColor Yellow
    }
}

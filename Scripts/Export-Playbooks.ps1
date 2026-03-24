<#
.SYNOPSIS
    Exports Logic App playbooks from an Azure Resource Group as parameterised ARM templates.

.DESCRIPTION
    Bulk-exports all Logic Apps (Sentinel playbooks) from a specified Resource Group,
    auto-detects their trigger type (Incident, Entity, Alert, Module, Watchlist), and
    writes parameterised ARM templates matching the Sentinel-As-Code conventions.

    The script:
    - Lists all Logic Apps in the target Resource Group via the Azure REST API
    - Classifies each playbook by inspecting its trigger (Incident, Entity, Module, etc.)
    - Builds a clean ARM template with parameterised connections, metadata, and tags
    - Replaces hardcoded subscription/RG/location values with ARM expressions
    - Writes each template to Playbooks/{Category}/{Name}.json

    Designed for PowerShell 7+ on macOS, Linux, and Windows. Uses Invoke-AzRestMethod
    exclusively (no Az.LogicApp dependency).

.PARAMETER SubscriptionId
    The Azure Subscription ID. If not provided, uses the current Az context.

.PARAMETER ResourceGroup
    The Resource Group containing the Logic Apps to export.

.PARAMETER OutputPath
    The output directory for exported templates. Defaults to ../Playbooks relative
    to this script.

.PARAMETER NameFilter
    Optional wildcard filter on Logic App names (e.g. 'Module-*', '*Defender*').

.PARAMETER Author
    Author name for the metadata block. Defaults to 'noodlemctwoodle'.

.PARAMETER Force
    Overwrite existing files without prompting.

.NOTES
    Author:         noodlemctwoodle
    Version:        1.0.0
    Last Updated:   2026-03-24
    Repository:     Sentinel-As-Code
    Requires:       Az.Accounts (PowerShell 7+)

.EXAMPLE
    .\Export-Playbooks.ps1 -ResourceGroup "rg-sentinel-automation"

    Exports all playbooks from the resource group to the default Playbooks/ folder.

.EXAMPLE
    .\Export-Playbooks.ps1 -ResourceGroup "rg-sentinel-automation" -NameFilter "Module-*" -Force

    Exports only Module playbooks, overwriting any existing files.

.EXAMPLE
    .\Export-Playbooks.ps1 -ResourceGroup "rg-sentinel-automation" -OutputPath "./export"

    Exports all playbooks to a custom output directory.
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
    [string]$OutputPath
    ,
    [Parameter(Mandatory = $false)]
    [string]$NameFilter
    ,
    [Parameter(Mandatory = $false)]
    [string]$Author = "noodlemctwoodle"
    ,
    [Parameter(Mandatory = $false)]
    [switch]$Force
)

#Requires -Modules Az.Accounts

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$InformationPreference = "Continue"

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
$script:LogicAppApiVersion = "2019-05-01"
$script:ConnectionApiVersion = "2016-06-01"

# ---------------------------------------------------------------------------
# Resolve paths
# ---------------------------------------------------------------------------
if (-not $OutputPath) {
    $OutputPath = Join-Path (Split-Path $PSScriptRoot -Parent) "Playbooks"
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Write-Status {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Message,
        [ValidateSet("Info", "Success", "Warning", "Error", "Section")]
        [string]$Level = "Info"
    )
    switch ($Level) {
        "Section" { Write-Information "`n=== $Message ===" }
        "Success" { Write-Information "  [OK] $Message" }
        "Warning" { Write-Warning $Message }
        "Error"   { Write-Error $Message }
        default   { Write-Information "  $Message" }
    }
}

function Get-SafeProperty {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    try {
        $prop = $Object.PSObject.Properties[$Name]
        if ($null -ne $prop) { return $prop.Value }
    }
    catch {
        # Object doesn't support PSObject property access
    }
    return $null
}

function Get-PropertyNames {
    param($Object)
    if ($null -eq $Object) { return @() }
    try {
        $names = [System.Collections.ArrayList]::new()
        foreach ($p in $Object.PSObject.Properties) {
            [void]$names.Add($p.Name)
        }
        return [string[]]$names
    }
    catch {
        return [string[]]@()
    }
}

function Invoke-AzureRestMethod {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Path,
        [string]$ApiVersion,
        [string]$Method = "GET"
    )

    $separator = if ($Path.Contains('?')) { '&' } else { '?' }
    $uri = "${Path}${separator}api-version=${ApiVersion}"
    $response = Invoke-AzRestMethod -Path $uri -Method $Method

    if ($response.StatusCode -ge 400) {
        throw "REST call failed ($($response.StatusCode)): $($response.Content)"
    }

    return ($response.Content | ConvertFrom-Json)
}

function Get-TriggerCategory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Definition
    )

    $triggers = Get-SafeProperty $Definition 'triggers'
    if (-not $triggers) { return "Other" }

    $triggerNames = Get-PropertyNames $triggers
    foreach ($triggerName in $triggerNames) {
        $trigger = $triggers.$triggerName
        $triggerType = Get-SafeProperty $trigger 'type'
        $triggerKind = Get-SafeProperty $trigger 'kind'
        $inputs = Get-SafeProperty $trigger 'inputs'
        $path = Get-SafeProperty $inputs 'path'

        if ($triggerType -eq "ApiConnectionWebhook") {
            if ($path -match "/incident-creation") { return "Incident" }
            if ($path -match "/entity/")           { return "Entity" }
            if ($path -match "/subscribe")          { return "Alert" }
        }

        if ($triggerType -eq "Request" -and $triggerKind -eq "Http") {
            return "Module"
        }

        if ($triggerType -eq "ApiConnection") {
            if ($path -match "/watchlist") { return "Watchlist" }
        }
    }

    # Check actions for watchlist references
    $actions = Get-SafeProperty $Definition 'actions'
    if ($actions) {
        $actionsJson = $actions | ConvertTo-Json -Depth 50 -Compress
        if ($actionsJson -match "watchlist") { return "Watchlist" }
    }

    return "Other"
}

function Get-ApiConnectorDisplayName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$ManagedApiId
    )

    # Extract the API name from the managed API path
    # e.g. .../managedApis/azuresentinel -> Azuresentinel
    if ($ManagedApiId -match "/managedApis/(.+)$") {
        $apiName = $Matches[1]
        # Map known API names to display-friendly names
        $displayMap = @{
            "azuresentinel"              = "MicrosoftSentinel"
            "wdatp"                      = "MicrosoftDefenderXDR"
            "office365"                  = "Office365"
            "teams"                      = "MicrosoftTeams"
            "azuread"                    = "AzureAD"
            "keyvault"                   = "AzureKeyVault"
            "azureloganalytics"          = "AzureLogAnalytics"
            "azuremonitorlogs"           = "AzureMonitorLogs"
            "servicebus"                 = "AzureServiceBus"
            "azureblob"                  = "AzureBlobStorage"
            "sharepointonline"           = "SharePointOnline"
            "cognitiveservicestextanalytics" = "CognitiveServicesTextAnalytics"
            "microsoftgraphsecurity"     = "MicrosoftGraphSecurity"
            "arm"                        = "AzureResourceManager"
            "microsoftsentinel"          = "MicrosoftSentinel"
        }
        $lower = $apiName.ToLower()
        if ($displayMap.ContainsKey($lower)) {
            return $displayMap[$lower]
        }
        # Fallback: PascalCase the API name
        return ($apiName.Substring(0, 1).ToUpper() + $apiName.Substring(1))
    }
    return "Unknown"
}

function Build-ConnectionVariables {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [hashtable]$ConnectionMap
    )

    $variables = [ordered]@{}
    foreach ($entry in $ConnectionMap.GetEnumerator()) {
        $variables[$entry.Value.VariableName] = "[concat('$($entry.Value.DisplayName)-', parameters('PlaybookName'))]"
    }
    return $variables
}

function Build-ConnectionResources {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [hashtable]$ConnectionMap
    )

    $resources = [System.Collections.ArrayList]::new()
    foreach ($entry in $ConnectionMap.GetEnumerator()) {
        $conn = $entry.Value
        $resource = [ordered]@{
            type       = "Microsoft.Web/connections"
            apiVersion = $script:ConnectionApiVersion
            name       = "[variables('$($conn.VariableName)')]"
            location   = "[resourceGroup().location]"
            kind       = "V1"
            properties = [ordered]@{
                displayName          = "[variables('$($conn.VariableName)')]"
                customParameterValues = @{}
                parameterValueType   = "Alternative"
                api                  = [ordered]@{
                    id = "[concat('/subscriptions/', subscription().subscriptionId, '/providers/Microsoft.Web/locations/', resourceGroup().location, '/managedApis/$($conn.ApiName)')]"
                }
            }
        }
        [void]$resources.Add($resource)
    }
    return $resources
}

function Build-ConnectionParameters {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [hashtable]$ConnectionMap
    )

    $connectionValues = [ordered]@{}
    foreach ($entry in $ConnectionMap.GetEnumerator()) {
        $conn = $entry.Value
        $connectionValues[$entry.Key] = [ordered]@{
            connectionId         = "[resourceId('Microsoft.Web/connections', variables('$($conn.VariableName)'))]"
            connectionName       = "[variables('$($conn.VariableName)')]"
            id                   = "[concat('/subscriptions/', subscription().subscriptionId, '/providers/Microsoft.Web/locations/', resourceGroup().location, '/managedApis/$($conn.ApiName)')]"
            connectionProperties = [ordered]@{
                authentication = [ordered]@{
                    type = "ManagedServiceIdentity"
                }
            }
        }
    }
    return $connectionValues
}

function Sanitize-WorkflowDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Definition,
        [Parameter(Mandatory)] [string]$SubscriptionId,
        [Parameter(Mandatory)] [string]$ResourceGroupName,
        [Parameter(Mandatory)] [string]$Category
    )

    # Convert to JSON, replace hardcoded IDs with ARM expressions, convert back
    $json = $Definition | ConvertTo-Json -Depth 100

    # Replace hardcoded subscription ID
    $json = $json -replace [regex]::Escape($SubscriptionId), "', subscription().subscriptionId, '"

    # Replace hardcoded resource group for Module workflow references
    # Pattern: /resourceGroups/{rgName}/providers/Microsoft.Logic/workflows/
    $rgPattern = "/resourceGroups/$([regex]::Escape($ResourceGroupName))/providers/Microsoft\.Logic/workflows/"
    $rgReplacement = "/resourceGroups/', parameters('AutomationResourceGroup'), '/providers/Microsoft.Logic/workflows/"
    $json = $json -replace $rgPattern, $rgReplacement

    # Clean up any double-concat artifacts from nested replacements
    # The workflow references should use [concat()] in the final ARM template
    # but within the definition JSON they use plain strings that get evaluated at runtime

    return ($json | ConvertFrom-Json)
}

function Build-ArmTemplate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $LogicApp,
        [Parameter(Mandatory)] [string]$Category,
        [Parameter(Mandatory)] [string]$PlaybookName,
        [Parameter(Mandatory)] [string]$AuthorName,
        [Parameter(Mandatory)] [string]$SubscriptionId,
        [Parameter(Mandatory)] [string]$ResourceGroupName
    )

    $definition = $LogicApp.properties.definition
    $params = Get-SafeProperty $LogicApp.properties 'parameters'
    $existingConnParams = Get-SafeProperty $params '$connections'

    # ----- Discover connections -----
    $connectionMap = [ordered]@{}
    $connValues = Get-SafeProperty $existingConnParams 'value'
    $connNames = Get-PropertyNames $connValues
    if (@($connNames).Count -gt 0) {

        # Track display name counts for indexing
        $displayCounts = @{}

        foreach ($connName in $connNames) {
            $connDetail = $connValues.$connName
            $apiId = $null

            if ($null -eq $connDetail) {
                $apiId = "/managedApis/$connName"
            }
            elseif ($connDetail -is [string]) {
                # Some connections store just a resource ID string
                $apiId = $connDetail
            }
            else {
                $connProps = Get-PropertyNames $connDetail
                if ($connProps -contains 'id')           { $apiId = $connDetail.id }
                if (-not $apiId -and ($connProps -contains 'connectionId')) { $apiId = $connDetail.connectionId }
            }

            if (-not $apiId) {
                $apiId = "/managedApis/$connName"
            }
            $displayName = Get-ApiConnectorDisplayName -ManagedApiId $apiId
            $apiName = if ($apiId -match "/managedApis/(.+)$") { $Matches[1] } else { $connName }

            # Build indexed variable name
            if (-not $displayCounts.ContainsKey($displayName)) {
                $displayCounts[$displayName] = 0
            }
            $index = $displayCounts[$displayName]
            $displayCounts[$displayName]++

            $variableName = if ($displayCounts[$displayName] -eq 1 -and @($connNames).Count -eq 1) {
                "${displayName}ConnectionName"
            }
            else {
                "${displayName}${index}ConnectionName"
            }

            $connectionMap[$connName] = @{
                DisplayName  = $displayName
                ApiName      = $apiName
                VariableName = $variableName
                Index        = $index
            }
        }
    }

    # ----- Parameters -----
    $parameters = [ordered]@{
        PlaybookName = [ordered]@{
            defaultValue = $PlaybookName
            type         = "string"
        }
    }

    $needsRgAndWorkspace = $Category -in @("Incident", "Entity", "Alert", "Watchlist")
    if ($needsRgAndWorkspace) {
        $parameters["AutomationResourceGroup"] = [ordered]@{
            defaultValue = ""
            type         = "string"
        }
        $parameters["SentinelWorkpaceName"] = [ordered]@{
            defaultValue = ""
            type         = "string"
        }
    }

    # ----- Variables -----
    $variables = Build-ConnectionVariables -ConnectionMap $connectionMap

    # ----- Sanitize definition (replace hardcoded IDs) -----
    $cleanDefinition = Sanitize-WorkflowDefinition `
        -Definition $definition `
        -SubscriptionId $SubscriptionId `
        -ResourceGroupName $ResourceGroupName `
        -Category $Category

    # ----- Build workflow resource -----
    $workflowProperties = [ordered]@{
        provisioningState = "Succeeded"
        state             = "Enabled"
        definition        = $cleanDefinition
    }

    # Add connection parameters if any connections exist
    if ($connectionMap.Count -gt 0) {
        $workflowProperties["parameters"] = [ordered]@{
            '$connections' = [ordered]@{
                value = Build-ConnectionParameters -ConnectionMap $connectionMap
            }
        }
    }

    # Add access control for Module playbooks
    if ($Category -eq "Module") {
        $workflowProperties["accessControl"] = [ordered]@{
            triggers = [ordered]@{ allowedCallerIpAddresses = @() }
            actions  = [ordered]@{ allowedCallerIpAddresses = @() }
        }
    }

    # Build tags
    $tags = [ordered]@{
        Source                          = "Sentinel-As-Code"
        "hidden-SentinelTemplateName"   = "${Category}-${PlaybookName}"
        "hidden-SentinelTemplateVersion" = "1.0"
    }
    if ($needsRgAndWorkspace) {
        $tags["hidden-SentinelWorkspaceId"] = "[concat('/subscriptions/', subscription().subscriptionId, '/resourceGroups/', parameters('AutomationResourceGroup'), '/providers/microsoft.OperationalInsights/Workspaces/', parameters('SentinelWorkpaceName'))]"
    }

    # Build dependsOn for connections
    $dependsOn = @()
    foreach ($entry in $connectionMap.GetEnumerator()) {
        $dependsOn += "[resourceId('Microsoft.Web/connections', variables('$($entry.Value.VariableName)'))]"
    }

    $workflowResource = [ordered]@{
        properties = $workflowProperties
        name       = "[parameters('PlaybookName')]"
        type       = "Microsoft.Logic/workflows"
        location   = "[resourceGroup().location]"
        tags       = $tags
        identity   = [ordered]@{ type = "SystemAssigned" }
        apiVersion = "2017-07-01"
        dependsOn  = $dependsOn
    }

    # ----- Build connection resources -----
    $connectionResources = Build-ConnectionResources -ConnectionMap $connectionMap

    # ----- Assemble resources array -----
    $resources = [System.Collections.ArrayList]::new()
    [void]$resources.Add($workflowResource)
    foreach ($cr in $connectionResources) {
        [void]$resources.Add($cr)
    }

    # ----- Build metadata -----
    $today = Get-Date -Format "dd-MM-yyyy"
    $metadata = [ordered]@{
        title          = "${Category}-${PlaybookName}"
        description    = $(
            $desc = Get-SafeProperty $LogicApp.properties.definition 'description'
            if ($desc) { $desc } else { "${Category} playbook: ${PlaybookName}" }
        )
        lastUpdateTime = $today
        entities       = @()
        tags           = @()
        support        = [ordered]@{ tier = "community" }
        author         = [ordered]@{ name = $AuthorName }
    }

    # ----- Final ARM template -----
    $template = [ordered]@{
        '$schema'      = "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#"
        contentVersion = "1.0.0.0"
        metadata       = $metadata
        parameters     = $parameters
        variables      = $variables
        resources      = $resources
    }

    return $template
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
function Main {
    Write-Status "Export Sentinel Playbooks" -Level Section

    # Validate Az context
    $context = Get-AzContext
    if (-not $context) {
        throw "No Azure context found. Run Connect-AzAccount first."
    }

    if ($SubscriptionId) {
        if ($context.Subscription.Id -ne $SubscriptionId) {
            Write-Status "Switching to subscription $SubscriptionId"
            Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
            $context = Get-AzContext
        }
    }

    $subId = $context.Subscription.Id
    Write-Status "Subscription: $subId ($($context.Subscription.Name))"
    Write-Status "Resource Group: $ResourceGroup"
    Write-Status "Output Path: $OutputPath"

    # List Logic Apps via REST
    Write-Status "Listing Logic Apps" -Level Section
    $listPath = "/subscriptions/${subId}/resourceGroups/${ResourceGroup}/providers/Microsoft.Logic/workflows"
    $result = Invoke-AzureRestMethod -Path "${listPath}?`$top=100" -ApiVersion $script:LogicAppApiVersion

    $logicApps = [System.Collections.ArrayList]::new()
    foreach ($item in $result.value) { [void]$logicApps.Add($item) }
    Write-Status "  Page 1: $(@($result.value).Count) Logic Apps"

    # Handle pagination - the REST API returns nextLink when there are more results
    $page = 1
    while ((Get-SafeProperty $result 'nextLink')) {
        $page++
        $response = Invoke-AzRestMethod -Uri $result.nextLink -Method GET
        if ($response.StatusCode -ge 400) {
            throw "REST pagination call failed ($($response.StatusCode)): $($response.Content)"
        }
        $result = $response.Content | ConvertFrom-Json
        foreach ($item in $result.value) { [void]$logicApps.Add($item) }
        Write-Status "  Page ${page}: $(@($result.value).Count) Logic Apps"
    }

    $logicApps = @($logicApps)
    if ($logicApps.Count -eq 0) {
        Write-Status "No Logic Apps found in resource group '$ResourceGroup'" -Level Warning
        return
    }

    # Apply name filter
    if ($NameFilter) {
        $logicApps = @($logicApps | Where-Object { $_.name -like $NameFilter })
        Write-Status "Filtered to $($logicApps.Count) Logic Apps matching '$NameFilter'"
    }

    Write-Status "Found $($logicApps.Count) Logic App(s) to export"

    # Process each Logic App
    $exported = 0
    $skipped = 0
    $errors = 0

    foreach ($app in $logicApps) {
        $appName = $app.name
        Write-Status "Processing: $appName" -Level Info

        try {
            # Get full Logic App details
            $detailPath = "/subscriptions/${subId}/resourceGroups/${ResourceGroup}/providers/Microsoft.Logic/workflows/${appName}"
            $fullApp = Invoke-AzureRestMethod -Path $detailPath -ApiVersion $script:LogicAppApiVersion

            # Detect category
            $definition = Get-SafeProperty $fullApp.properties 'definition'
            if (-not $definition) {
                Write-Status "  SKIPPED (no workflow definition found)" -Level Warning
                $skipped++
                continue
            }
            $category = Get-TriggerCategory -Definition $definition
            Write-Status "  Category: $category"

            # Derive playbook name (strip category prefix if present)
            $playbookName = $appName
            foreach ($prefix in @("Incident-", "Entity-", "Module-", "Alert-", "Watchlist-")) {
                if ($appName.StartsWith($prefix)) {
                    $playbookName = $appName.Substring($prefix.Length)
                    break
                }
            }

            # Build ARM template
            $template = Build-ArmTemplate `
                -LogicApp $fullApp `
                -Category $category `
                -PlaybookName $playbookName `
                -AuthorName $Author `
                -SubscriptionId $subId `
                -ResourceGroupName $ResourceGroup

            # Determine output file path
            $categoryDir = Join-Path $OutputPath $category
            if (-not (Test-Path $categoryDir)) {
                New-Item -Path $categoryDir -ItemType Directory -Force | Out-Null
            }

            $outputFile = Join-Path $categoryDir "${playbookName}.json"

            # Check for existing file
            if ((Test-Path $outputFile) -and -not $Force) {
                Write-Status "  SKIPPED (file exists, use -Force to overwrite): $outputFile" -Level Warning
                $skipped++
                continue
            }

            # Write template
            $json = $template | ConvertTo-Json -Depth 100
            # Fix escaped ARM expression brackets that ConvertTo-Json double-escapes
            # ConvertTo-Json wraps the strings fine, no bracket escaping needed for JSON
            Set-Content -Path $outputFile -Value $json -Encoding utf8NoBOM

            Write-Status "  Exported: $outputFile" -Level Success
            $exported++
        }
        catch {
            $stackLines = $_.ScriptStackTrace -split "`n" | Select-Object -First 3
            Write-Status "  FAILED to export '$appName': $($_.Exception.Message)" -Level Warning
            foreach ($sl in $stackLines) { Write-Status "    $($sl.Trim())" }
            $errors++
        }
    }

    # Summary
    Write-Status "Export Complete" -Level Section
    Write-Status "  Exported: $exported"
    if ($skipped -gt 0) { Write-Status "  Skipped:  $skipped" }
    if ($errors -gt 0)  { Write-Status "  Errors:   $errors" -Level Warning }
}

Main

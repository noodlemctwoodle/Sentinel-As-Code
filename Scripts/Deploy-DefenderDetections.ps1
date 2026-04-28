<#
.SYNOPSIS
    Deploys custom detection rules to Microsoft Defender XDR via the Graph Security API.

.DESCRIPTION
    This script automates the deployment of custom detection rules stored as YAML files
    in the repository to the Microsoft Defender XDR platform using the Microsoft Graph
    Security API (beta).

    Custom detections use Advanced Hunting KQL queries and can trigger alerts and
    automated response actions (device isolation, investigation packages, etc.).

    The script authenticates using the existing Azure context (Service Principal or
    Managed Identity) and acquires a Microsoft Graph token.

    Key capabilities:
    - Deploy custom detection rules from YAML files
    - Create new rules or update existing rules (matched by displayName)
    - Support for all schedule periods (NRT, 1H, 3H, 12H, 24H)
    - Support for impacted assets and response actions
    - WhatIf mode for dry runs

.PARAMETER BasePath
    The root path of the repository containing the DefenderCustomDetections/ folder.
    Defaults to the parent of the Scripts folder.

.PARAMETER IsGov
    When specified, targets the Azure Government cloud environment.
    Uses the US Government Graph endpoint (graph.microsoft.us).

.PARAMETER WhatIf
    When specified, performs a dry run showing what actions would be taken without
    making changes.

.NOTES
    Author:         noodlemctwoodle
    Version:        1.0.1
    Last Updated:   2026-04-28
    Repository:     Sentinel-As-Code
    API:            Microsoft Graph Security API (beta)
    Requires:       Az.Accounts, powershell-yaml
    Permissions:    CustomDetection.ReadWrite.All (Application)

.EXAMPLE
    .\Deploy-DefenderDetections.ps1

    Deploys all custom detection rules from the DefenderCustomDetections/ folder.

.EXAMPLE
    .\Deploy-DefenderDetections.ps1 -WhatIf

    Performs a dry run showing what rules would be deployed.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$BasePath
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
$script:GraphBaseUrl = if ($IsGov) {
    "https://graph.microsoft.us"
} else {
    "https://graph.microsoft.com"
}

$script:GraphApiVersion = "beta"
$script:DetectionRulesEndpoint = "$($script:GraphBaseUrl)/$($script:GraphApiVersion)/security/rules/detectionRules"

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
# Helper: Invoke Graph API with retry logic
# ---------------------------------------------------------------------------
function Invoke-GraphApi {
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

            # Graph API throttling: respect Retry-After header
            if ($statusCode -eq 429 -and $attempt -lt $MaxRetries) {
                $retryAfter = $RetryDelaySeconds * $attempt
                try {
                    $retryAfterHeader = $_.Exception.Response.Headers.GetValues("Retry-After") | Select-Object -First 1
                    if ($retryAfterHeader) {
                        $retryAfter = [int]$retryAfterHeader
                    }
                }
                catch {}
                Write-PipelineMessage "Graph API throttled (429). Retrying in ${retryAfter}s (attempt $attempt of $MaxRetries)..." -Level Warning
                Start-Sleep -Seconds $retryAfter
                continue
            }

            if ($statusCode -and $retryableCodes -contains $statusCode -and $attempt -lt $MaxRetries) {
                $delay = $RetryDelaySeconds * $attempt
                Write-PipelineMessage "Graph API returned $statusCode. Retrying in ${delay}s (attempt $attempt of $MaxRetries)..." -Level Warning
                Start-Sleep -Seconds $delay
                continue
            }

            $errorDetail = $_.Exception.Message
            if ($_.ErrorDetails.Message) {
                $errorDetail = "HTTP $statusCode - $($_.ErrorDetails.Message)"
            }

            throw "Graph API call failed: $errorDetail"
        }
    }
}

# ---------------------------------------------------------------------------
# Authentication: Acquire Microsoft Graph token
# ---------------------------------------------------------------------------
function Connect-GraphEnvironment {
    [CmdletBinding()]
    param()

    Write-PipelineMessage "Establishing Microsoft Graph authentication..." -Level Section

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

    Write-PipelineMessage "Authenticated as: $($context.Account.Id) (Tenant: $($context.Tenant.Id))" -Level Success

    # Acquire a Graph API token using the existing Azure context
    $graphResource = $script:GraphBaseUrl
    try {
        $tokenResponse = Get-AzAccessToken -ResourceUrl $graphResource -ErrorAction Stop

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
        throw "Failed to acquire Microsoft Graph token. Ensure the Service Principal has 'CustomDetection.ReadWrite.All' Graph application permission with admin consent. Error: $($_.Exception.Message)"
    }

    if (-not $accessToken) {
        throw "Failed to acquire a Graph access token."
    }

    $script:GraphAuthHeader = @{
        'Content-Type'  = 'application/json'
        'Authorization' = "Bearer $accessToken"
    }

    Write-PipelineMessage "Graph API endpoint: $($script:DetectionRulesEndpoint)" -Level Info
    if ($IsGov) {
        Write-PipelineMessage "Azure Government cloud mode enabled (graph.microsoft.us)." -Level Info
    }
}

# ---------------------------------------------------------------------------
# Get existing detection rules for upsert matching
# ---------------------------------------------------------------------------
function Get-ExistingDetectionRules {
    [CmdletBinding()]
    param()

    Write-PipelineMessage "Fetching existing custom detection rules..." -Level Info

    $allRules = @()
    $uri = $script:DetectionRulesEndpoint

    try {
        # Handle pagination
        while ($uri) {
            $response = Invoke-GraphApi -Uri $uri -Method Get -Headers $script:GraphAuthHeader
            if ($response.value) {
                $allRules += $response.value
            }
            $uri = if ($response.PSObject.Properties['@odata.nextLink']) { $response.'@odata.nextLink' } else { $null }
        }

        Write-PipelineMessage "Found $($allRules.Count) existing custom detection rule(s)." -Level Info
        return $allRules
    }
    catch {
        Write-PipelineMessage "Could not fetch existing rules: $($_.Exception.Message). All rules will be created as new." -Level Warning
        return @()
    }
}

# ---------------------------------------------------------------------------
# Convert YAML rule definition to Graph API request body
# ---------------------------------------------------------------------------
function ConvertTo-GraphDetectionBody {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Rule
    )

    # Build the detection action
    $alertTemplate = @{
        title     = $Rule['detectionAction']['alertTemplate']['title']
        severity  = $Rule['detectionAction']['alertTemplate']['severity']
        category  = $Rule['detectionAction']['alertTemplate']['category']
    }

    # Optional alert template fields
    if ($Rule['detectionAction']['alertTemplate'].ContainsKey('description')) {
        $alertTemplate.description = $Rule['detectionAction']['alertTemplate']['description']
    }
    if ($Rule['detectionAction']['alertTemplate'].ContainsKey('mitreTechniques')) {
        $alertTemplate.mitreTechniques = [array]$Rule['detectionAction']['alertTemplate']['mitreTechniques']
    }
    if ($Rule['detectionAction']['alertTemplate'].ContainsKey('recommendedActions')) {
        $alertTemplate.recommendedActions = $Rule['detectionAction']['alertTemplate']['recommendedActions']
    }
    if ($Rule['detectionAction']['alertTemplate'].ContainsKey('impactedAssets')) {
        $alertTemplate.impactedAssets = [array]$Rule['detectionAction']['alertTemplate']['impactedAssets']
    }

    $detectionAction = @{
        alertTemplate       = $alertTemplate
        organizationalScope = $null
    }

    if ($Rule['detectionAction'].ContainsKey('responseActions')) {
        $detectionAction.responseActions = [array]$Rule['detectionAction']['responseActions']
    }
    else {
        $detectionAction.responseActions = @()
    }

    # Build the query condition
    $queryCondition = @{
        queryText = $Rule['queryCondition']['queryText']
    }
    if ($Rule['queryCondition'].ContainsKey('lastModifiedDateTime')) {
        $queryCondition.lastModifiedDateTime = $Rule['queryCondition']['lastModifiedDateTime']
    }

    # Build the full body
    $body = @{
        displayName     = $Rule['displayName']
        isEnabled       = if ($Rule.ContainsKey('isEnabled')) { [bool]$Rule['isEnabled'] } else { $true }
        queryCondition  = $queryCondition
        schedule        = @{
            period = $Rule['schedule']['period']
        }
        detectionAction = $detectionAction
    }

    return $body
}

# ---------------------------------------------------------------------------
# Deploy Custom Detection Rules
# ---------------------------------------------------------------------------
function Deploy-DefenderDetections {
    [CmdletBinding()]
    param()

    $counters = @{ Created = 0; Updated = 0; Skipped = 0; Failed = 0 }
    $detectionsPath = Join-Path $BasePath "DefenderCustomDetections"

    Write-PipelineMessage "Deploying Defender XDR custom detection rules..." -Level Section

    if (-not (Test-Path $detectionsPath)) {
        Write-PipelineMessage "DefenderCustomDetections folder not found at '$detectionsPath' — skipping." -Level Warning
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

    # Fetch existing rules for upsert matching (match by displayName)
    $existingRules = @()
    if (-not $WhatIf) {
        $existingRules = Get-ExistingDetectionRules
    }
    $existingRuleMap = @{}
    foreach ($existing in $existingRules) {
        if ($existing.displayName) {
            $existingRuleMap[$existing.displayName] = $existing.id
        }
    }

    foreach ($file in $yamlFiles) {
        try {
            $yamlContent = Get-Content -Path $file.FullName -Raw
            $rule = ConvertFrom-Yaml -Yaml $yamlContent

            # Validate required fields
            if (-not $rule.ContainsKey('displayName') -or [string]::IsNullOrWhiteSpace($rule['displayName'])) {
                Write-PipelineMessage "Skipping '$($file.Name)': missing required field 'displayName'." -Level Warning
                $counters.Skipped++
                continue
            }
            if (-not $rule.ContainsKey('queryCondition') -or -not $rule['queryCondition'].ContainsKey('queryText')) {
                Write-PipelineMessage "Skipping '$($file.Name)': missing required field 'queryCondition.queryText'." -Level Warning
                $counters.Skipped++
                continue
            }
            if (-not $rule.ContainsKey('schedule') -or -not $rule['schedule'].ContainsKey('period')) {
                Write-PipelineMessage "Skipping '$($file.Name)': missing required field 'schedule.period'." -Level Warning
                $counters.Skipped++
                continue
            }
            if (-not $rule.ContainsKey('detectionAction') -or -not $rule['detectionAction'].ContainsKey('alertTemplate')) {
                Write-PipelineMessage "Skipping '$($file.Name)': missing required field 'detectionAction.alertTemplate'." -Level Warning
                $counters.Skipped++
                continue
            }

            $alertTemplate = $rule['detectionAction']['alertTemplate']
            $requiredAlertFields = @('title', 'severity', 'category')
            $missingAlertFields = @($requiredAlertFields | Where-Object { -not $alertTemplate.ContainsKey($_) -or [string]::IsNullOrWhiteSpace($alertTemplate[$_]) })
            if ($missingAlertFields.Count -gt 0) {
                Write-PipelineMessage "Skipping '$($file.Name)': alertTemplate missing required fields: $($missingAlertFields -join ', ')." -Level Warning
                $counters.Skipped++
                continue
            }

            # Validate schedule period
            # Note: '0' (NRT/continuous) is listed in the Graph API ruleSchedule schema but
            # Microsoft only documents NRT configuration via the portal UI. No API example
            # uses period "0". It is accepted here since the schema permits it, but may not
            # work as expected. Use the Defender portal for NRT rules.
            $validPeriods = @('0', '1H', '3H', '12H', '24H')
            if ($validPeriods -notcontains $rule['schedule']['period']) {
                Write-PipelineMessage "Skipping '$($file.Name)': invalid schedule period '$($rule['schedule']['period'])'. Valid values: $($validPeriods -join ', ')." -Level Warning
                $counters.Skipped++
                continue
            }

            $ruleName = $rule['displayName']
            $schedulePeriod = $rule['schedule']['period']
            $scheduleDisplay = if ($schedulePeriod -eq '0') { 'NRT' } else { "Every $schedulePeriod" }

            if ($schedulePeriod -eq '0') {
                Write-PipelineMessage "Warning: NRT (period '0') is defined in the Graph API schema but only documented for portal configuration. API deployment may not work as expected." -Level Warning
            }

            Write-PipelineMessage "Processing: $ruleName ($scheduleDisplay) [$($file.Name)]" -Level Info

            # Convert YAML to Graph API body
            $bodyObj = ConvertTo-GraphDetectionBody -Rule $rule
            $body = $bodyObj | ConvertTo-Json -Depth 20

            if ($WhatIf) {
                Write-PipelineMessage "[WhatIf] Would deploy detection: $ruleName (Schedule: $scheduleDisplay, Severity: $($alertTemplate['severity']))" -Level Info
                $counters.Created++
            }
            else {
                # Check if rule already exists (match by displayName)
                if ($existingRuleMap.ContainsKey($ruleName)) {
                    $existingId = $existingRuleMap[$ruleName]
                    $uri = "$($script:DetectionRulesEndpoint)/$existingId"
                    Invoke-GraphApi -Uri $uri -Method Patch -Headers $script:GraphAuthHeader -Body $body | Out-Null
                    Write-PipelineMessage "Updated: $ruleName (ID: $existingId)" -Level Success
                    $counters.Updated++
                }
                else {
                    $result = Invoke-GraphApi -Uri $script:DetectionRulesEndpoint -Method Post -Headers $script:GraphAuthHeader -Body $body
                    $newId = $result.id
                    Write-PipelineMessage "Created: $ruleName (ID: $newId)" -Level Success
                    $counters.Created++
                }
            }
        }
        catch {
            Write-PipelineMessage "Failed to deploy '$($file.Name)': $($_.Exception.Message)" -Level Error
            if ($body) {
                Write-PipelineMessage "Request body: $body" -Level Warning
            }
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
        [hashtable]$Counters
        ,
        [Parameter(Mandatory = $true)]
        [timespan]$Duration
    )

    Write-PipelineMessage "Defender XDR Custom Detections Deployment Summary" -Level Section
    Write-PipelineMessage ("=" * 60) -Level Info

    $total = $Counters.Created + $Counters.Updated + $Counters.Skipped + $Counters.Failed
    Write-PipelineMessage "  Created:  $($Counters.Created)" -Level Info
    Write-PipelineMessage "  Updated:  $($Counters.Updated)" -Level Info
    Write-PipelineMessage "  Skipped:  $($Counters.Skipped)" -Level Info
    Write-PipelineMessage "  Failed:   $($Counters.Failed)" -Level Info
    Write-PipelineMessage ("=" * 60) -Level Info
    Write-PipelineMessage "  Total:    $total" -Level Info
    Write-PipelineMessage "  Duration: $($Duration.ToString('hh\:mm\:ss'))" -Level Info

    if ($Counters.Failed -gt 0) {
        Write-PipelineMessage "$($Counters.Failed) rule(s) failed to deploy. Review errors above." -Level Error
    }
    elseif (($Counters.Created + $Counters.Updated) -gt 0) {
        Write-PipelineMessage "All rules deployed successfully." -Level Success
    }

    return $Counters.Failed
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
function Main {
    $scriptStartTime = Get-Date

    Write-PipelineMessage ("=" * 60) -Level Info
    Write-PipelineMessage "  Sentinel-As-Code: Defender XDR Custom Detections" -Level Section
    Write-PipelineMessage ("=" * 60) -Level Info

    if ($WhatIf) {
        Write-PipelineMessage "DRY RUN MODE — no changes will be made." -Level Warning
    }

    Write-PipelineMessage "Configuration:" -Level Info
    Write-PipelineMessage "  Base Path:  $BasePath" -Level Info
    Write-PipelineMessage "  Graph URL:  $($script:GraphBaseUrl)" -Level Info
    Write-PipelineMessage "  Endpoint:   $($script:DetectionRulesEndpoint)" -Level Info

    Connect-GraphEnvironment

    $counters = Deploy-DefenderDetections

    $duration = (Get-Date) - $scriptStartTime
    $totalFailed = Write-DeploymentSummary -Counters $counters -Duration $duration

    if ($totalFailed -gt 0) {
        exit 1
    }
}

Main

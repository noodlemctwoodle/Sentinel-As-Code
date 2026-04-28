<#
.SYNOPSIS
    Detects drift between Microsoft Sentinel Analytics Rules deployed in a workspace and
    their source-of-truth (Content Hub template or repo YAML).

.DESCRIPTION
    Read-only detection script that compares every Analytics Rule deployed in a Sentinel
    workspace against the rule's source-of-truth and reports any divergence. This catches
    rules that have been modified directly in the Sentinel portal, bypassing the DevOps
    deployment pipelines.

    For each deployed rule, the script resolves a source:

    - 'ContentHub'  : rule has a populated 'alertRuleTemplateName' that matches a Content
                      Hub contentTemplate's contentId. Compared against that template.
    - 'Custom'      : rule's resource name matches the 'id:' GUID of a YAML file under
                      AnalyticalRules/. Compared against the YAML.
    - 'Orphan'      : rule has neither a template link nor a matching repo YAML. Reported
                      as ungoverned.

    The comparison surface mirrors the drift logic used in Deploy-SentinelContentHub.ps1
    (Test-RuleIsCustomised) and adds 'displayName'. Entity mappings, tactics, techniques,
    customDetails, alertDetailsOverride, incidentConfiguration, and 'enabled' are NOT
    compared. Their JSON shapes differ between API responses, ARM templates, and YAML
    (causing unactionable false positives), and 'enabled' specifically is routinely
    overridden away from the YAML/template intent by deployment-time switches like
    -DisableRules or by automatic disable-on-missing-dependency logic.

    Built-in Microsoft-managed rule kinds (Fusion, MicrosoftSecurityIncidentCreation,
    MLBehaviorAnalytics, ThreatIntelligence) are excluded from drift detection — their
    content is not user-editable and they have no source-of-truth in the deploy model.
    They are reported in the 'managed' summary count for visibility.

    When drift is detected the script:

    - **Custom drift** : surgically rewrites the matched YAML file under AnalyticalRules/
                         to reflect the deployed state, then bumps its patch version. The
                         pipeline that invokes this script is responsible for committing
                         and PR'ing the resulting file changes.
    - **ContentHub**   : reported in reports/sentinel-drift-latest.{md,json} only. No
                         repo edits — Microsoft owns Content Hub templates, and the deploy
                         pipeline already auto-protects modified OoB rules via
                         Deploy-SentinelContentHub.ps1's -ProtectCustomisedRules switch.
    - **Orphan**       : reported in reports/sentinel-drift-latest.{md,json} only.
                         Adopting orphans into governance is a manual triage step.

    When NO drift is detected the script writes nothing — the working tree stays clean so
    the invoking pipeline does not open an empty PR.

    Pass -ReportOnly to suppress YAML edits (still writes the report).
    Pass -FailOnDrift to make the pipeline fail when any drift is detected.

.PARAMETER SubscriptionId
    Azure Subscription ID containing the Sentinel workspace. Falls back to current Azure
    context if not provided.

.PARAMETER ResourceGroup
    Resource Group containing the Sentinel workspace.

.PARAMETER Workspace
    Log Analytics workspace name with Sentinel enabled.

.PARAMETER Region
    Azure region of the workspace (e.g. 'uksouth').

.PARAMETER Solutions
    Optional list of Content Hub solution display names to scope OoB drift detection to
    (e.g. 'Microsoft Defender XDR'). Empty (default) scans all OoB rules.
    Custom and Orphan buckets are not affected by this filter.

.PARAMETER SeveritiesToInclude
    Optional severity filter applied to all three buckets.

.PARAMETER RepoPath
    Repository root containing the AnalyticalRules/ folder. Defaults to the parent of the
    Scripts/ folder this script lives in.

.PARAMETER ReportOnly
    Skip YAML edits for Custom drift; still writes the report files. Useful when running
    locally to inspect drift before letting the pipeline auto-sync.

.PARAMETER SkipContentHub
    Skip drift detection for rules linked to a Content Hub template. By default all
    three buckets are evaluated; this switch suppresses the ContentHub bucket.

.PARAMETER SkipCustom
    Skip drift detection for rules whose GUID matches a repo YAML. By default all
    three buckets are evaluated; this switch suppresses the Custom bucket.

.PARAMETER SkipOrphans
    Skip orphan reporting for rules with no source-of-truth match. By default all
    three buckets are evaluated; this switch suppresses the Orphan bucket.

.PARAMETER FailOnDrift
    Exit with code 1 when any drift OR orphan is detected. Default behaviour is exit 0
    (informational). Use this to gate downstream pipelines.

.PARAMETER IsGov
    Target the Azure Government cloud.

.PARAMETER WhatIf
    Skip writing the JSON/MD artefacts; ADO warnings and summary still emitted.

.NOTES
    Author:         noodlemctwoodle
    Version:        1.0.1
    Last Updated:   2026-04-28
    Repository:     Sentinel-As-Code
    API Version:    2025-09-01 (GA)
    Requires:       Az.Accounts, powershell-yaml

.EXAMPLE
    .\Test-SentinelRuleDrift.ps1 `
        -ResourceGroup "rg-sentinel-prod" `
        -Workspace "law-sentinel-prod" `
        -Region "uksouth"

    Scans the workspace. If drift is detected, rewrites matching Custom YAML files and
    writes reports/sentinel-drift-latest.{md,json}. If no drift, writes nothing.

.EXAMPLE
    .\Test-SentinelRuleDrift.ps1 `
        -ResourceGroup "rg-sentinel-prod" `
        -Workspace "law-sentinel-prod" `
        -Region "uksouth" `
        -ReportOnly

    Detection-only mode: write reports but never edit YAML files. Useful for local
    inspection before letting the pipeline auto-sync.
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
    [string[]]$Solutions = @()
    ,
    [Parameter(Mandatory = $false)]
    [ValidateSet("High", "Medium", "Low", "Informational")]
    [string[]]$SeveritiesToInclude = @("High", "Medium", "Low", "Informational")
    ,
    [Parameter(Mandatory = $false)]
    [string]$RepoPath = (Split-Path -Path $PSScriptRoot -Parent)
    ,
    [Parameter(Mandatory = $false)]
    [switch]$SkipContentHub
    ,
    [Parameter(Mandatory = $false)]
    [switch]$SkipCustom
    ,
    [Parameter(Mandatory = $false)]
    [switch]$SkipOrphans
    ,
    [Parameter(Mandatory = $false)]
    [switch]$ReportOnly
    ,
    [Parameter(Mandatory = $false)]
    [switch]$FailOnDrift
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
$script:SentinelApiVersion = "2025-09-01"

# Reserved for future use; full text is always written to JSON and Markdown so reviewers
# can see the complete diff. Intentionally kept here to make the constant easy to find
# if we ever need to bound JSON size for huge KQL queries.
$script:DiffSnippetLength = 0

# Built-in / Microsoft-managed rule kinds. Content is not user-editable, so drift
# detection doesn't apply — they're counted under summary.managed and skipped from
# all three buckets (ContentHub / Custom / Orphan).
$script:ManagedRuleKinds = @(
    'Fusion',
    'MicrosoftSecurityIncidentCreation',
    'MLBehaviorAnalytics',
    'ThreatIntelligence'
)

# ---------------------------------------------------------------------------
# Helper: Write ADO pipeline commands where applicable, otherwise standard output
# TODO: extract to Sentinel.Common.psm1 — duplicated in
#   Scripts/Deploy-SentinelContentHub.ps1:191
#   Scripts/Deploy-CustomContent.ps1:515
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
# TODO: extract to Sentinel.Common.psm1 — duplicated in
#   Scripts/Deploy-SentinelContentHub.ps1:285
#   Scripts/Deploy-CustomContent.ps1:574
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
# Authentication
# TODO: extract to Sentinel.Common.psm1 — duplicated in
#   Scripts/Deploy-SentinelContentHub.ps1:412
#   Scripts/Deploy-CustomContent.ps1:654
# ---------------------------------------------------------------------------
function Connect-AzureEnvironment {
    [CmdletBinding()]
    param()

    Write-PipelineMessage "Establishing Azure authentication..." -Level Section

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
# Deployed rule discovery
# ---------------------------------------------------------------------------
function Get-ExistingAnalyticsRules {
    [CmdletBinding()]
    param()

    Write-PipelineMessage "Fetching deployed Analytics Rules..." -Level Info

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
    Write-PipelineMessage "Found $($rules.Count) deployed Analytics Rules." -Level Info
    return ,$rules
}

# ---------------------------------------------------------------------------
# Content Hub template discovery
# ---------------------------------------------------------------------------
function Get-ContentHubAnalyticsRuleTemplates {
    [CmdletBinding()]
    param()

    Write-PipelineMessage "Fetching Content Hub Analytics Rule templates..." -Level Info

    $templatesUrl = "$($script:BaseUri)/providers/Microsoft.SecurityInsights/contentTemplates?api-version=$($script:SentinelApiVersion)&`$filter=(properties/contentKind eq 'AnalyticsRule')&`$expand=properties/mainTemplate"
    $templateList = [System.Collections.Generic.List[object]]::new()
    $result = Invoke-SentinelApi -Uri $templatesUrl -Method Get -Headers $script:AuthHeader
    if ($result.PSObject.Properties.Name -contains "value") {
        foreach ($t in $result.value) { $templateList.Add($t) }
    }

    while ($result.PSObject.Properties.Name -contains "nextLink" -and $result.nextLink) {
        $result = Invoke-SentinelApi -Uri $result.nextLink -Method Get -Headers $script:AuthHeader
        if ($result.PSObject.Properties.Name -contains "value") {
            foreach ($t in $result.value) { $templateList.Add($t) }
        }
    }

    $templates = @($templateList)
    Write-PipelineMessage "Found $($templates.Count) Content Hub Analytics Rule templates." -Level Info
    return ,$templates
}

# ---------------------------------------------------------------------------
# Content Hub solution catalogue (for packageId -> solution displayName mapping)
# ---------------------------------------------------------------------------
function Get-ContentHubSolutionLookup {
    [CmdletBinding()]
    param()

    $lookup = @{}
    try {
        $url = "$($script:BaseUri)/providers/Microsoft.SecurityInsights/contentProductPackages?api-version=$($script:SentinelApiVersion)"
        $result = Invoke-SentinelApi -Uri $url -Method Get -Headers $script:AuthHeader

        $packages = @(if ($result.PSObject.Properties.Name -contains "value") { $result.value } else { @() })

        while ($result.PSObject.Properties.Name -contains "nextLink" -and $result.nextLink) {
            $result = Invoke-SentinelApi -Uri $result.nextLink -Method Get -Headers $script:AuthHeader
            if ($result.PSObject.Properties.Name -contains "value") { $packages += $result.value }
        }

        foreach ($pkg in $packages) {
            $displayName = if ($pkg.properties.PSObject.Properties.Name -contains "displayName") { $pkg.properties.displayName } else { $null }
            $contentId = if ($pkg.properties.PSObject.Properties.Name -contains "contentId") { $pkg.properties.contentId } else { $pkg.name }
            if ($displayName -and $contentId) {
                $lookup[$contentId] = $displayName
            }
        }
        Write-PipelineMessage "Mapped $($lookup.Count) Content Hub package IDs to solution names." -Level Info
    }
    catch {
        Write-PipelineMessage "Could not fetch Content Hub solution catalogue: $($_.Exception.Message). Solution names will be unavailable in the report." -Level Warning
    }
    return $lookup
}

# ---------------------------------------------------------------------------
# Repo YAML discovery
# ---------------------------------------------------------------------------
function Get-RepoAnalyticsRuleYamls {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot
    )

    $rulesPath = Join-Path -Path $RepoRoot -ChildPath "AnalyticalRules"

    if (-not (Test-Path -Path $rulesPath)) {
        Write-PipelineMessage "AnalyticalRules folder not found at '$rulesPath' — Custom drift detection disabled." -Level Warning
        return @{}
    }

    if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
        Write-PipelineMessage "Installing powershell-yaml module..." -Level Info
        Install-Module -Name powershell-yaml -Force -Scope CurrentUser -AllowClobber
    }
    Import-Module powershell-yaml -ErrorAction Stop

    $yamlFiles = @(Get-ChildItem -Path $rulesPath -Include "*.yaml", "*.yml" -Recurse -File)
    $byGuid = @{}
    $skipped = 0

    foreach ($file in $yamlFiles) {
        try {
            $content = Get-Content -Path $file.FullName -Raw
            $parsed = ConvertFrom-Yaml -Yaml $content

            if (-not $parsed.ContainsKey('id') -or [string]::IsNullOrWhiteSpace($parsed['id'])) {
                $skipped++
                continue
            }

            $guid = ($parsed['id']).ToString().ToLowerInvariant()
            $byGuid[$guid] = @{
                FilePath  = $file.FullName
                IsCommunity = ($file.FullName -match '[/\\]Community[/\\]')
                Yaml      = $parsed
            }
        }
        catch {
            Write-PipelineMessage "Failed to parse YAML '$($file.FullName)': $($_.Exception.Message)" -Level Warning
            $skipped++
        }
    }

    Write-PipelineMessage "Indexed $($byGuid.Count) repo YAML rule(s); skipped $skipped." -Level Info
    return $byGuid
}

# ---------------------------------------------------------------------------
# Normalisation helpers — bring YAML, ARM template and deployed-rule shapes into
# a common comparison surface.
# ---------------------------------------------------------------------------
function Convert-TriggerOperator {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    # Mirrors Scripts/Deploy-CustomContent.ps1:1185-1192
    $map = @{
        'gt' = 'GreaterThan'; 'greaterthan' = 'GreaterThan'
        'lt' = 'LessThan';    'lessthan'    = 'LessThan'
        'eq' = 'Equal';       'equal'       = 'Equal'
        'ne' = 'NotEqual';    'notequal'    = 'NotEqual'
    }
    $key = $Value.ToString().ToLowerInvariant()
    if ($map.ContainsKey($key)) { return $map[$key] }
    return $Value.ToString()
}

# Inverse of Convert-TriggerOperator: API form -> YAML short form. Used when writing
# drift back to a YAML file so the file matches the repo's style guide.
function ConvertTo-ShortTriggerOperator {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    $map = @{
        'greaterthan' = 'gt'
        'lessthan'    = 'lt'
        'equal'       = 'eq'
        'notequal'    = 'ne'
    }
    $key = $Value.ToString().ToLowerInvariant()
    if ($map.ContainsKey($key)) { return $map[$key] }
    return $Value.ToString()
}

function Convert-Severity {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    $lower = $Value.ToString().ToLowerInvariant()
    switch ($lower) {
        'high'          { return 'High' }
        'medium'        { return 'Medium' }
        'low'           { return 'Low' }
        'informational' { return 'Informational' }
        default         { return $Value.ToString() }
    }
}

function Convert-QueryWhitespace {
    param([string]$Value)
    if ($null -eq $Value) { return $null }
    return ($Value -replace '\s+', ' ').Trim()
}

function ConvertTo-NormalisedYamlRule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [hashtable]$YamlEntry
    )

    $yaml = $YamlEntry.Yaml
    $kind = if ($yaml.ContainsKey('kind')) { [string]$yaml['kind'] } else { 'Scheduled' }

    $enabled = $true
    if ($YamlEntry.IsCommunity) { $enabled = $false }
    elseif ($yaml.ContainsKey('enabled')) { $enabled = [bool]$yaml['enabled'] }

    $normalised = @{
        kind        = $kind
        displayName = if ($yaml.ContainsKey('name')) { [string]$yaml['name'] } else { $null }
        severity    = if ($yaml.ContainsKey('severity')) { Convert-Severity ([string]$yaml['severity']) } else { $null }
        query       = if ($yaml.ContainsKey('query')) { Convert-QueryWhitespace ([string]$yaml['query']) } else { $null }
        enabled     = $enabled
    }

    if ($kind -ne 'NRT') {
        $normalised.queryFrequency   = if ($yaml.ContainsKey('queryFrequency'))   { [string]$yaml['queryFrequency'] }   else { $null }
        $normalised.queryPeriod      = if ($yaml.ContainsKey('queryPeriod'))      { [string]$yaml['queryPeriod'] }      else { $null }
        $normalised.triggerOperator  = if ($yaml.ContainsKey('triggerOperator'))  { Convert-TriggerOperator ([string]$yaml['triggerOperator']) } else { $null }
        $normalised.triggerThreshold = if ($yaml.ContainsKey('triggerThreshold')) { [int]$yaml['triggerThreshold'] }     else { $null }
    }

    return $normalised
}

function ConvertTo-NormalisedTemplateRule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object]$Template
    )

    if (-not ($Template.properties.PSObject.Properties.Name -contains 'mainTemplate') -or
        $null -eq $Template.properties.mainTemplate) {
        return $null
    }

    $mainTemplate = $Template.properties.mainTemplate
    if (-not ($mainTemplate.PSObject.Properties.Name -contains 'resources') -or
        $null -eq $mainTemplate.resources -or
        $mainTemplate.resources.Count -eq 0) {
        return $null
    }

    $ruleResource = $mainTemplate.resources |
        Where-Object {
            $_.PSObject.Properties.Name -contains 'type' -and
            ($_.type -like '*alertRules*' -or $_.type -eq 'Microsoft.OperationalInsights/workspaces/providers/alertRules')
        } |
        Select-Object -First 1

    if (-not $ruleResource) { $ruleResource = $mainTemplate.resources[0] }

    if (-not ($ruleResource.PSObject.Properties.Name -contains 'properties') -or $null -eq $ruleResource.properties) {
        return $null
    }

    $props = $ruleResource.properties
    $kind = if ($ruleResource.PSObject.Properties.Name -contains 'kind') { [string]$ruleResource.kind } else { 'Scheduled' }

    $normalised = @{
        kind        = $kind
        displayName = if ($props.PSObject.Properties.Name -contains 'displayName') { [string]$props.displayName } else { $null }
        severity    = if ($props.PSObject.Properties.Name -contains 'severity')    { Convert-Severity ([string]$props.severity) } else { $null }
        query       = if ($props.PSObject.Properties.Name -contains 'query')       { Convert-QueryWhitespace ([string]$props.query) } else { $null }
    }

    # Templates rarely include 'enabled'; deployed rules default to whatever the deployer set.
    # Skip enabled comparison for ContentHub-sourced rules to avoid noisy false positives —
    # the DisableRules deployment switch routinely flips this away from the template.
    $normalised.enabled = $null

    if ($kind -ne 'NRT') {
        $normalised.queryFrequency   = if ($props.PSObject.Properties.Name -contains 'queryFrequency')   { [string]$props.queryFrequency } else { $null }
        $normalised.queryPeriod      = if ($props.PSObject.Properties.Name -contains 'queryPeriod')      { [string]$props.queryPeriod }    else { $null }
        $normalised.triggerOperator  = if ($props.PSObject.Properties.Name -contains 'triggerOperator')  { Convert-TriggerOperator ([string]$props.triggerOperator) } else { $null }
        $normalised.triggerThreshold = if ($props.PSObject.Properties.Name -contains 'triggerThreshold') { [int]$props.triggerThreshold } else { $null }
    }

    return $normalised
}

function ConvertTo-NormalisedDeployedRule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object]$Rule
    )

    $props = $Rule.properties
    $kind = if ($Rule.PSObject.Properties.Name -contains 'kind') { [string]$Rule.kind } else { 'Scheduled' }

    $normalised = @{
        kind        = $kind
        displayName = if ($props.PSObject.Properties.Name -contains 'displayName') { [string]$props.displayName } else { $null }
        severity    = if ($props.PSObject.Properties.Name -contains 'severity')    { Convert-Severity ([string]$props.severity) } else { $null }
        query       = if ($props.PSObject.Properties.Name -contains 'query')       { Convert-QueryWhitespace ([string]$props.query) } else { $null }
        enabled     = if ($props.PSObject.Properties.Name -contains 'enabled')     { [bool]$props.enabled } else { $null }
    }

    if ($kind -ne 'NRT') {
        $normalised.queryFrequency   = if ($props.PSObject.Properties.Name -contains 'queryFrequency')   { [string]$props.queryFrequency } else { $null }
        $normalised.queryPeriod      = if ($props.PSObject.Properties.Name -contains 'queryPeriod')      { [string]$props.queryPeriod }    else { $null }
        $normalised.triggerOperator  = if ($props.PSObject.Properties.Name -contains 'triggerOperator')  { Convert-TriggerOperator ([string]$props.triggerOperator) } else { $null }
        $normalised.triggerThreshold = if ($props.PSObject.Properties.Name -contains 'triggerThreshold') { [int]$props.triggerThreshold } else { $null }
    }

    return $normalised
}

# ---------------------------------------------------------------------------
# Surgically rewrite a YAML rule file so the modified fields match the deployed
# state. Single-line scalars are replaced via line-anchored regex; the multi-line
# `query: |` block is replaced as a whole. All other content (description,
# requiredDataConnectors, entityMappings, tags, etc.) is preserved byte-for-byte.
#
# Also bumps the patch component of `version:` so the smart-deploy logic in
# Deploy-CustomContent.ps1 picks up the change.
# ---------------------------------------------------------------------------
function Update-RuleYamlFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$FilePath
        ,
        [Parameter(Mandatory)] [array]$Modifications  # array of @{ Field; Deployed; Expected }
    )

    $original = Get-Content -Path $FilePath -Raw
    $text = $original
    $textBeforeFieldEdits = $text

    foreach ($mod in $Modifications) {
        $field = $mod.Field
        $newValue = $mod.Deployed     # we are pulling drift FROM the deployed state INTO the YAML
        if ($null -eq $newValue) { continue }

        switch ($field) {
            'severity' {
                $text = [regex]::Replace($text, '(?m)^severity:[ \t]*\S.*$', "severity: $newValue")
            }
            'displayName' {
                # YAML field is `name`, not `displayName`. Quote if it contains characters
                # that YAML would misinterpret; otherwise leave bare.
                $needsQuoting = $newValue -match '[:#\[\]\{\}&*!|>''""%@`,]' -or $newValue -match '^\s|\s$'
                $rendered = if ($needsQuoting) { ("'" + ($newValue -replace "'", "''") + "'") } else { $newValue }
                $text = [regex]::Replace($text, '(?m)^name:[ \t]*\S.*$', "name: $rendered")
            }
            'queryFrequency' {
                $text = [regex]::Replace($text, '(?m)^queryFrequency:[ \t]*\S+', "queryFrequency: $newValue")
            }
            'queryPeriod' {
                $text = [regex]::Replace($text, '(?m)^queryPeriod:[ \t]*\S+', "queryPeriod: $newValue")
            }
            'triggerOperator' {
                $shortOp = ConvertTo-ShortTriggerOperator $newValue
                $text = [regex]::Replace($text, '(?m)^triggerOperator:[ \t]*\S+', "triggerOperator: $shortOp")
            }
            'triggerThreshold' {
                $text = [regex]::Replace($text, '(?m)^triggerThreshold:[ \t]*\S+', "triggerThreshold: $newValue")
            }
            'query' {
                # Replace the entire `query: |` block (block scalar) up to the next
                # top-level key. Preserves the leading 2-space indent that the repo's
                # YAML style uses for block-scalar bodies.
                #
                # Note: do NOT use the (?s) flag — with single-line mode '.' matches
                # newlines and the indented-line matcher will swallow whole subsequent
                # sections (entityMappings, eventGroupingSettings, etc). Keep '.' bound
                # to a single line via [^\r\n].
                $indented = (($newValue -split "`r?`n") | ForEach-Object { "  $_" }) -join "`n"
                $blockReplacement = "query: |`n$indented`n"
                $text = [regex]::Replace($text, '(?m)^query:[ \t]*\|[^\r\n]*\r?\n(?:[ \t][^\r\n]*\r?\n?)*?(?=^[A-Za-z][\w-]*:)', $blockReplacement)
            }
        }
    }

    # Bump patch version ONLY if at least one field edit actually fired. Otherwise
    # passing in a modification list with only unrecognised fields would still
    # bump the version, churning the YAML for no real reason.
    $fieldEditsApplied = ($text -ne $textBeforeFieldEdits)
    if ($fieldEditsApplied -and
        $text -match '(?m)^version:[ \t]*([0-9]+)\.([0-9]+)\.([0-9]+)\b') {
        $major = [int]$Matches[1]; $minor = [int]$Matches[2]; $patch = [int]$Matches[3] + 1
        $newVersion = "$major.$minor.$patch"
        $text = [regex]::Replace($text, '(?m)^version:[ \t]*[0-9]+\.[0-9]+\.[0-9]+\b', "version: $newVersion")
    }

    if ($text -ne $original) {
        Set-Content -Path $FilePath -Value $text -NoNewline -Encoding UTF8
        return $true
    }
    return $false
}

# ---------------------------------------------------------------------------
# Compare a deployed rule against its expected source.
# Mirrors the field set of Test-RuleIsCustomised in Deploy-SentinelContentHub.ps1:826
# and adds 'displayName'. 'enabled' is NOT compared — Deploy-CustomContent.ps1
# routinely deploys rules as enabled=false when dependencies are missing or KQL
# validation fails, and Deploy-SentinelContentHub.ps1's -DisableRules switch
# does the same for OoB content. Comparing 'enabled' produces unactionable
# false-positives on every rule deployed via either of those paths.
# Returns a structured diff for the JSON artefact.
# ---------------------------------------------------------------------------
function Compare-SentinelRule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [hashtable]$Deployed
        ,
        [Parameter(Mandatory)] [hashtable]$Expected
    )

    $modifications = @()

    $kind = $Deployed['kind']
    $isNrt = ($kind -eq 'NRT')

    $fieldsScheduled = @('query', 'queryFrequency', 'queryPeriod', 'triggerOperator', 'triggerThreshold', 'severity', 'displayName')
    $fieldsNrt       = @('query', 'severity', 'displayName')
    $fields = if ($isNrt) { $fieldsNrt } else { $fieldsScheduled }

    foreach ($field in $fields) {
        if (-not $Expected.ContainsKey($field)) { continue }
        $expectedValue = $Expected[$field]
        if ($null -eq $expectedValue) { continue }   # template/YAML did not specify this field

        $deployedValue = if ($Deployed.ContainsKey($field)) { $Deployed[$field] } else { $null }

        if ($field -eq 'severity' -or $field -eq 'triggerOperator') {
            $eq = ([string]$deployedValue -ieq [string]$expectedValue)
        }
        else {
            $eq = ($deployedValue -eq $expectedValue)
        }

        if (-not $eq) {
            $modifications += @{
                Field    = $field
                Deployed = $deployedValue
                Expected = $expectedValue
            }
        }
    }

    return @{
        HasDrift      = ($modifications.Count -gt 0)
        Modifications = $modifications
    }
}

# ---------------------------------------------------------------------------
# Resolve the source-of-truth for a deployed rule.
# Returns @{ Source = 'ContentHub' | 'Custom' | 'Orphan'; Expected; SourceRef; Solution }
# ---------------------------------------------------------------------------
function Resolve-RuleSource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object]$Rule
        ,
        [Parameter(Mandatory)] [hashtable]$TemplatesByContentId
        ,
        [Parameter(Mandatory)] [hashtable]$YamlsByGuid
        ,
        [Parameter(Mandatory)] [hashtable]$SolutionByPackageId
    )

    $templateName = $null
    if ($Rule.PSObject.Properties.Name -contains 'properties' -and
        $Rule.properties.PSObject.Properties.Name -contains 'alertRuleTemplateName') {
        $templateName = $Rule.properties.alertRuleTemplateName
    }

    if (-not [string]::IsNullOrWhiteSpace($templateName) -and
        $TemplatesByContentId.ContainsKey($templateName)) {

        $template = $TemplatesByContentId[$templateName]
        $expected = ConvertTo-NormalisedTemplateRule -Template $template

        $packageId = if ($template.properties.PSObject.Properties.Name -contains 'packageId') { $template.properties.packageId } else { $null }
        $solutionName = if ($packageId -and $SolutionByPackageId.ContainsKey($packageId)) { $SolutionByPackageId[$packageId] } else { $null }

        return @{
            Source    = 'ContentHub'
            Expected  = $expected
            SourceRef = $templateName
            Solution  = $solutionName
        }
    }

    $ruleGuid = if ($Rule.PSObject.Properties.Name -contains 'name') { ([string]$Rule.name).ToLowerInvariant() } else { $null }
    if ($ruleGuid -and $YamlsByGuid.ContainsKey($ruleGuid)) {
        $entry = $YamlsByGuid[$ruleGuid]
        $expected = ConvertTo-NormalisedYamlRule -YamlEntry $entry

        return @{
            Source    = 'Custom'
            Expected  = $expected
            SourceRef = $entry.FilePath
            Solution  = $null
        }
    }

    return @{
        Source    = 'Orphan'
        Expected  = $null
        SourceRef = $null
        Solution  = $null
    }
}

# ---------------------------------------------------------------------------
# Compute a unified line-level diff for multi-line field values via the
# longest-common-subsequence algorithm. Output mirrors `git diff` (without the
# file headers) so the +/- lines appear in the order they occur in the file.
# No external dependency — KQL queries are typically <100 lines so the
# O(m*n) LCS table is fine.
# ---------------------------------------------------------------------------
function Get-LineDiff {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$Before
        ,
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$After
    )

    $a = @($Before -split "`r?`n")
    $b = @($After  -split "`r?`n")
    $m = $a.Count
    $n = $b.Count

    # Build the LCS length table as a jagged array — PowerShell's $arr[i,j]
    # syntax slices a 1D array rather than indexing a 2D one, so jagged keeps
    # the algorithm idiomatic.
    $L = New-Object 'int[][]' ($m + 1)
    for ($k = 0; $k -le $m; $k++) {
        $L[$k] = New-Object 'int[]' ($n + 1)
    }

    for ($i = 1; $i -le $m; $i++) {
        for ($j = 1; $j -le $n; $j++) {
            if ($a[$i - 1] -ceq $b[$j - 1]) {
                $L[$i][$j] = $L[$i - 1][$j - 1] + 1
            }
            else {
                $L[$i][$j] = [Math]::Max($L[$i - 1][$j], $L[$i][$j - 1])
            }
        }
    }

    # Walk back from the corner, emitting unchanged / + / - lines in reverse
    $out = New-Object 'System.Collections.Generic.List[string]'
    $i = $m; $j = $n
    while ($i -gt 0 -and $j -gt 0) {
        if ($a[$i - 1] -ceq $b[$j - 1]) {
            $out.Insert(0, "  " + $a[$i - 1])
            $i--; $j--
        }
        elseif ($L[$i - 1][$j] -ge $L[$i][$j - 1]) {
            $out.Insert(0, "- " + $a[$i - 1])
            $i--
        }
        else {
            $out.Insert(0, "+ " + $b[$j - 1])
            $j--
        }
    }
    while ($i -gt 0) { $out.Insert(0, "- " + $a[$i - 1]); $i-- }
    while ($j -gt 0) { $out.Insert(0, "+ " + $b[$j - 1]); $j-- }

    return ($out -join "`n")
}

# Multi-line heuristic — fields with newlines render as fenced blocks; everything
# else renders inline. The KQL query is the obvious multi-line case in practice.
function Test-IsMultiLine {
    param($Value)
    if ($null -eq $Value) { return $false }
    return ([string]$Value).IndexOf("`n") -ge 0 -or ([string]$Value).Length -gt 120
}

# Render one drift field block in markdown. Short scalars get an inline
# `Deployed: `X` -> Expected: `Y`` line; multi-line values get a fenced diff
# plus full deployed and expected blocks so nothing is truncated.
function Format-FieldBlock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object]$Modification
        ,
        [Parameter(Mandatory)] [string]$DeployedLabel
        ,
        [Parameter(Mandatory)] [string]$ExpectedLabel
    )

    $sb = [System.Text.StringBuilder]::new()
    $field = $Modification.field
    $dep   = $Modification.deployed
    $exp   = $Modification.expected

    $depMulti = Test-IsMultiLine $dep
    $expMulti = Test-IsMultiLine $exp

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("##### ``$field``")
    [void]$sb.AppendLine("")

    if (-not $depMulti -and -not $expMulti) {
        # Inline scalar: one line, both values shown verbatim
        $depRendered = if ($null -eq $dep) { '*(unset)*' } else { '`' + $dep + '`' }
        $expRendered = if ($null -eq $exp) { '*(unset)*' } else { '`' + $exp + '`' }
        [void]$sb.AppendLine("- ${DeployedLabel}: $depRendered")
        [void]$sb.AppendLine("- ${ExpectedLabel}: $expRendered")
        return $sb.ToString()
    }

    # Multi-line: render diff + full bodies
    [void]$sb.AppendLine("Diff (lines starting ``-`` are ${ExpectedLabel}, ``+`` are ${DeployedLabel}):")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine('```diff')
    [void]$sb.AppendLine((Get-LineDiff -Before ([string]$exp) -After ([string]$dep)))
    [void]$sb.AppendLine('```')

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("**${DeployedLabel} (full):**")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine('```kql')
    [void]$sb.AppendLine([string]$dep)
    [void]$sb.AppendLine('```')

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("**${ExpectedLabel} (full):**")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine('```kql')
    [void]$sb.AppendLine([string]$exp)
    [void]$sb.AppendLine('```')

    return $sb.ToString()
}

# ---------------------------------------------------------------------------
# Always emit ADO warnings + summary to the live pipeline log, regardless of
# whether files are written.
# ---------------------------------------------------------------------------
function Write-DriftSummary {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable]$Report)

    foreach ($d in $Report.drifted) {
        $fields = ($d.modifiedFields | ForEach-Object { $_.field }) -join ', '
        Write-PipelineMessage "DRIFT [$($d.source)] '$($d.displayName)' ($($d.ruleName)): modified fields = $fields" -Level Warning
    }
    foreach ($o in $Report.orphans) {
        Write-PipelineMessage "ORPHAN '$($o.displayName)' ($($o.ruleName)): no source-of-truth — created or detached in the portal." -Level Warning
    }

    Write-PipelineMessage "Drift summary:" -Level Section
    Write-PipelineMessage "  Total deployed rules : $($Report.summary.totalDeployed)" -Level Info
    Write-PipelineMessage "  ContentHub clean     : $($Report.summary.contentHubClean)" -Level Info
    Write-PipelineMessage "  ContentHub drift     : $($Report.summary.contentHubDrift)" -Level Info
    Write-PipelineMessage "  Custom clean         : $($Report.summary.customClean)" -Level Info
    Write-PipelineMessage "  Custom drift         : $($Report.summary.customDrift)" -Level Info
    Write-PipelineMessage "  Orphan rules         : $($Report.summary.orphan)" -Level Info
    Write-PipelineMessage "  Managed (excluded)   : $($Report.summary.managed)" -Level Info
}

# ---------------------------------------------------------------------------
# Write JSON + Markdown reports under reports/ in the repo. Only called when
# drift is detected — when the working tree should stay clean we never touch
# disk so the invoking pipeline doesn't open an empty PR.
# ---------------------------------------------------------------------------
function Write-DriftReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [hashtable]$Report
        ,
        [Parameter(Mandatory)] [string]$OutputDir
    )

    if (-not (Test-Path -Path $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    }

    # Timestamp the filename so two runs never collide — fixes the 'Added in both'
    # merge conflict that appeared when an earlier PR's reports/sentinel-drift-latest.*
    # was merged into main and a subsequent run wrote the same path on the rolling
    # auto-branch. Use ':' replaced with '-' for filesystem portability.
    $stamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH-mmZ")
    $jsonPath = Join-Path -Path $OutputDir -ChildPath "sentinel-drift-$stamp.json"
    $Report | ConvertTo-Json -Depth 8 | Set-Content -Path $jsonPath -Encoding UTF8
    Write-PipelineMessage "Wrote drift report: $jsonPath" -Level Success

    $mdPath = Join-Path -Path $OutputDir -ChildPath "sentinel-drift-$stamp.md"
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("# Sentinel Analytics Rule Drift Report")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("- Generated: $($Report.generatedAt)")
    [void]$sb.AppendLine("- Subscription: $($Report.subscriptionId)")
    [void]$sb.AppendLine("- Resource Group: $($Report.resourceGroup)")
    [void]$sb.AppendLine("- Workspace: $($Report.workspace)")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("## Summary")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("| Bucket | Count |")
    [void]$sb.AppendLine("| --- | ---: |")
    [void]$sb.AppendLine("| Total deployed | $($Report.summary.totalDeployed) |")
    [void]$sb.AppendLine("| Content Hub clean | $($Report.summary.contentHubClean) |")
    [void]$sb.AppendLine("| Content Hub drift | $($Report.summary.contentHubDrift) |")
    [void]$sb.AppendLine("| Custom clean | $($Report.summary.customClean) |")
    [void]$sb.AppendLine("| Custom drift | $($Report.summary.customDrift) |")
    [void]$sb.AppendLine("| Orphan | $($Report.summary.orphan) |")
    [void]$sb.AppendLine("| Managed (excluded) | $($Report.summary.managed) |")

    $contentHubDrifted = @($Report.drifted | Where-Object { $_.source -eq 'ContentHub' })
    $customDrifted     = @($Report.drifted | Where-Object { $_.source -eq 'Custom' })

    if ($customDrifted.Count -gt 0) {
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("## Custom Rule Drift (auto-synced into repo)")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("These rules were edited in the Sentinel portal. The matching YAML files under ``AnalyticalRules/`` have been updated to reflect the deployed state. Compare against the **Files Changed** tab of this PR to see the YAML diff exactly as committed.")
        foreach ($d in $customDrifted) {
            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("### $($d.displayName)")
            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("- File: ``$($d.sourceRef)``")
            [void]$sb.AppendLine("- Rule GUID: ``$($d.ruleName)``")
            [void]$sb.AppendLine("- Kind: $($d.kind)")
            if ($d.PSObject.Properties.Name -contains 'yamlUpdated') {
                [void]$sb.AppendLine("- YAML updated: $($d.yamlUpdated)")
            }
            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("#### Modified fields")
            foreach ($m in $d.modifiedFields) {
                [void]$sb.Append((Format-FieldBlock -Modification $m -DeployedLabel "Deployed (now in YAML)" -ExpectedLabel "Previously in YAML"))
            }
        }
    }

    if ($contentHubDrifted.Count -gt 0) {
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("## Content Hub Drift (report only)")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("These rules diverge from their Content Hub template. The repo carries no source-of-truth for OoB rules, so no file is updated. The deploy pipeline already auto-protects these via ``-ProtectCustomisedRules``.")
        foreach ($d in $contentHubDrifted) {
            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("### $($d.displayName)")
            [void]$sb.AppendLine("")
            if ($d.solution)  { [void]$sb.AppendLine("- Solution: $($d.solution)") }
            if ($d.sourceRef) { [void]$sb.AppendLine("- Template: ``$($d.sourceRef)``") }
            [void]$sb.AppendLine("- Rule GUID: ``$($d.ruleName)``")
            [void]$sb.AppendLine("- Kind: $($d.kind)")
            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("#### Modified fields")
            foreach ($m in $d.modifiedFields) {
                [void]$sb.Append((Format-FieldBlock -Modification $m -DeployedLabel "Deployed" -ExpectedLabel "Template"))
            }
        }
    }

    if ($Report.orphans.Count -gt 0) {
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("## Orphan Rules (report only — manual triage required)")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("These rules were created directly in the Sentinel portal and have no source-of-truth in the repo. Adopting them into governance is a manual step.")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("| Display name | Rule GUID | Kind | Enabled |")
        [void]$sb.AppendLine("| --- | --- | --- | --- |")
        foreach ($o in $Report.orphans) {
            [void]$sb.AppendLine("| $($o.displayName) | $($o.ruleName) | $($o.kind) | $($o.enabled) |")
        }
    }

    Set-Content -Path $mdPath -Value $sb.ToString() -Encoding UTF8
    Write-PipelineMessage "Wrote markdown report: $mdPath" -Level Success
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
function Invoke-Main {
    Connect-AzureEnvironment

    $deployedRules = Get-ExistingAnalyticsRules
    $templates     = if (-not $SkipContentHub) { Get-ContentHubAnalyticsRuleTemplates } else { @() }
    $solutionMap   = if (-not $SkipContentHub) { Get-ContentHubSolutionLookup } else { @{} }
    $yamls         = if (-not $SkipCustom)     { Get-RepoAnalyticsRuleYamls -RepoRoot $RepoPath } else { @{} }

    $templatesByContentId = @{}
    foreach ($t in $templates) {
        $contentId = if ($t.properties.PSObject.Properties.Name -contains 'contentId') { $t.properties.contentId } else { $t.name }
        if ($contentId) { $templatesByContentId[$contentId] = $t }
    }

    # Solution-name filter: when -Solutions is supplied, restrict ContentHub comparison to
    # rules whose template's packageId resolves to one of the named solutions.
    $allowedPackageIds = $null
    if ($Solutions -and $Solutions.Count -gt 0) {
        $solutionsLower = @($Solutions | ForEach-Object { $_.ToLowerInvariant() })
        $allowedPackageIds = @{}
        foreach ($pkgId in $solutionMap.Keys) {
            if ($solutionsLower -contains $solutionMap[$pkgId].ToLowerInvariant()) {
                $allowedPackageIds[$pkgId] = $true
            }
        }
        Write-PipelineMessage "Solution filter active: $($Solutions -join ', ') -> $($allowedPackageIds.Keys.Count) packageId(s) matched." -Level Info
    }

    $summary = @{
        totalDeployed    = $deployedRules.Count
        contentHubClean  = 0
        contentHubDrift  = 0
        customClean      = 0
        customDrift      = 0
        orphan           = 0
        managed          = 0
        skipped          = 0
    }
    $drifted = [System.Collections.Generic.List[object]]::new()
    $orphans = [System.Collections.Generic.List[object]]::new()

    foreach ($rule in $deployedRules) {
        $deployedNorm = ConvertTo-NormalisedDeployedRule -Rule $rule

        if ($script:ManagedRuleKinds -contains $deployedNorm.kind) {
            $summary.managed++
            continue
        }

        if ($SeveritiesToInclude -and $deployedNorm.severity -and
            ($SeveritiesToInclude -notcontains $deployedNorm.severity)) {
            $summary.skipped++
            continue
        }
        if ($deployedNorm.displayName -and $deployedNorm.displayName -match '\[Deprecated\]') {
            $summary.skipped++
            continue
        }

        $resolved = Resolve-RuleSource `
            -Rule $rule `
            -TemplatesByContentId $templatesByContentId `
            -YamlsByGuid $yamls `
            -SolutionByPackageId $solutionMap

        switch ($resolved.Source) {
            'ContentHub' {
                if ($SkipContentHub) { $summary.skipped++; break }

                if ($null -ne $allowedPackageIds) {
                    $template = $templatesByContentId[$resolved.SourceRef]
                    $pkgId = if ($template.properties.PSObject.Properties.Name -contains 'packageId') { $template.properties.packageId } else { $null }
                    if (-not $pkgId -or -not $allowedPackageIds.ContainsKey($pkgId)) {
                        $summary.skipped++
                        break
                    }
                }

                if ($null -eq $resolved.Expected) {
                    Write-PipelineMessage "  Could not extract template properties for '$($deployedNorm.displayName)'; skipping." -Level Debug
                    $summary.skipped++
                    break
                }

                $diff = Compare-SentinelRule -Deployed $deployedNorm -Expected $resolved.Expected
                if ($diff.HasDrift) {
                    $summary.contentHubDrift++
                    $drifted.Add([pscustomobject]@{
                        ruleId         = $rule.id
                        ruleName       = $rule.name
                        displayName    = $deployedNorm.displayName
                        kind           = $deployedNorm.kind
                        source         = 'ContentHub'
                        sourceRef      = $resolved.SourceRef
                        solution       = $resolved.Solution
                        modifiedFields = @($diff.Modifications | ForEach-Object {
                            [pscustomobject]@{
                                field    = $_.Field
                                deployed = $_.Deployed
                                expected = $_.Expected
                            }
                        })
                    })
                }
                else {
                    $summary.contentHubClean++
                }
            }
            'Custom' {
                if ($SkipCustom) { $summary.skipped++; break }
                if ($null -eq $resolved.Expected) { $summary.skipped++; break }

                $diff = Compare-SentinelRule -Deployed $deployedNorm -Expected $resolved.Expected
                if ($diff.HasDrift) {
                    $summary.customDrift++
                    $drifted.Add([pscustomobject]@{
                        ruleId         = $rule.id
                        ruleName       = $rule.name
                        displayName    = $deployedNorm.displayName
                        kind           = $deployedNorm.kind
                        source         = 'Custom'
                        sourceRef      = $resolved.SourceRef
                        solution       = $null
                        modifiedFields = @($diff.Modifications | ForEach-Object {
                            [pscustomobject]@{
                                field    = $_.Field
                                deployed = $_.Deployed
                                expected = $_.Expected
                            }
                        })
                    })
                }
                else {
                    $summary.customClean++
                }
            }
            'Orphan' {
                if ($SkipOrphans) { $summary.skipped++; break }

                $summary.orphan++
                $orphans.Add([pscustomobject]@{
                    ruleId      = $rule.id
                    ruleName    = $rule.name
                    displayName = $deployedNorm.displayName
                    kind        = $deployedNorm.kind
                    enabled     = $deployedNorm.enabled
                })
            }
        }
    }

    # Apply Custom drift back to the YAML files. Each rewrite annotates the
    # report record so the markdown PR description tells reviewers what landed.
    if (-not $ReportOnly -and -not $WhatIf) {
        foreach ($entry in $drifted) {
            if ($entry.source -ne 'Custom') { continue }
            try {
                $changed = Update-RuleYamlFile -FilePath $entry.sourceRef -Modifications $entry.modifiedFields
                $entry | Add-Member -NotePropertyName 'yamlUpdated' -NotePropertyValue $changed -Force
                if ($changed) {
                    Write-PipelineMessage "  Synced YAML: $($entry.sourceRef)" -Level Success
                }
                else {
                    Write-PipelineMessage "  No-op on YAML: $($entry.sourceRef) (regex did not match — manual edit required)" -Level Warning
                }
            }
            catch {
                Write-PipelineMessage "  Failed to update '$($entry.sourceRef)': $($_.Exception.Message)" -Level Error
                $entry | Add-Member -NotePropertyName 'yamlUpdated' -NotePropertyValue $false -Force
            }
        }
    }

    $report = @{
        generatedAt    = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        workspace      = $Workspace
        subscriptionId = $script:SubscriptionId
        resourceGroup  = $ResourceGroup
        summary        = $summary
        drifted        = @($drifted)
        orphans        = @($orphans)
    }

    Write-DriftSummary -Report $report

    $hasDrift = ($summary.contentHubDrift + $summary.customDrift + $summary.orphan) -gt 0

    # Only write report files when there is something to report. Keeps the working
    # tree clean on no-drift runs so the pipeline does not open an empty PR.
    if ($hasDrift -and -not $WhatIf) {
        $reportsDir = Join-Path -Path $RepoPath -ChildPath "reports"
        Write-DriftReport -Report $report -OutputDir $reportsDir
    }
    elseif ($WhatIf) {
        Write-PipelineMessage "[WhatIf] Skipping report write." -Level Info
    }
    else {
        Write-PipelineMessage "No drift detected — skipping report write to keep working tree clean." -Level Info
    }

    if ($FailOnDrift -and $hasDrift) {
        Write-PipelineMessage "Drift detected; -FailOnDrift set, exiting 1." -Level Error
        exit 1
    }
}

Invoke-Main

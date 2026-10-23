#Requires -Version 7.2
#Requires -Modules Az.Accounts

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
    - Deploy custom detection rules from YAML files written in the current
      Graph detectionRule shape (status, ISO 8601 schedule.frequency,
      alertTemplate.tactics, entityMappings, automatedActions)
    - Update existing rules in place (matched by displayName) and create
      new ones with the file's client-provided id
    - Translate files that still use the fields Graph removed on
      2026-10-01 (isEnabled, schedule.period, category, mitreTechniques,
      impactedAssets, responseActions), with a warning naming each file
    - Schedule frequencies PT1H, PT3H, PT12H and P1D
    - WhatIf mode for dry runs

.PARAMETER BasePath
    The root path of the repository containing the DefenderCustomDetections/ folder.
    Defaults to the parent of the Deploy folder.

.PARAMETER IsGov
    When specified, targets the Azure Government cloud environment.
    Uses the US Government Graph endpoint (graph.microsoft.us). Microsoft
    does not offer the custom detection rules API in US Government clouds,
    so a run with -IsGov is expected to fail; the script warns and tries.

.PARAMETER WhatIf
    When specified, performs a dry run showing what actions would be taken without
    making changes.

.EXAMPLE
    .\Deploy-DefenderDetections.ps1

    Deploys all custom detection rules from the DefenderCustomDetections/ folder.

.EXAMPLE
    .\Deploy-DefenderDetections.ps1 -WhatIf

    Performs a dry run showing what rules would be deployed.

.NOTES
    File:           Deploy/content/Deploy-DefenderDetections.ps1
    Repository:     Sentinel-As-Code
    Author:         noodlemctwoodle
    Website:        https://sentinel.blog
    Created:        2026-03-20
    Version:        1.1.0
    Last Updated:   2026-10-23
    Permissions:    CustomDetection.ReadWrite.All (Application)
    Requires:       PowerShell 7.2+, Az.Accounts, powershell-yaml (auto-installed if missing)

    API versions:
      - Microsoft Graph Security : beta (custom detection rules are not yet
                                   on the v1.0 endpoint; the request shape
                                   is the one in place after the
                                   2026-10-01 field removals)

.LINK
    https://learn.microsoft.com/graph/api/resources/security-detectionrule?view=graph-rest-beta
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
    $BasePath = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
}

# ---------------------------------------------------------------------------
# Shared helpers from Sentinel.Common
# ---------------------------------------------------------------------------
# Defender uses only Write-PipelineMessage from the shared module —
# Graph API auth and HTTP wrappers are Defender-specific
# (Invoke-GraphApi / Connect-GraphEnvironment below) since they target
# the Microsoft Graph beta endpoint, not Sentinel's ARM-based endpoints.
Import-Module (Join-Path $PSScriptRoot '../../Modules/Sentinel.Common/Sentinel.Common.psd1') -Force -ErrorAction Stop

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
        Write-PipelineMessage "Azure Government cloud mode enabled (graph.microsoft.us). Microsoft does not offer the custom detection rules API in US Government clouds, so this run is expected to fail." -Level Warning
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
# Graph detectionRule contract (beta)
# ---------------------------------------------------------------------------
# Microsoft replaced the original custom detection fields on 2026-10-01:
# isEnabled became status, schedule.period became the ISO 8601
# schedule.frequency, alertTemplate.category and mitreTechniques became
# alertTemplate.tactics, impactedAssets became entityMappings and
# responseActions became automatedActions. The new entity mappings and
# automated actions name query result columns (DeviceId, AccountSid) where
# the old shape named identifier tokens (deviceId, accountSid).
function Get-DetectionContract {
    <#
    .SYNOPSIS
        Returns the Graph detectionRule contract tables the converters and
        the validator share (valid values, collections, legacy mappings).
    #>
    [CmdletBinding()]
    param()

    if (-not (Get-Variable -Name DetectionContract -Scope Script -ErrorAction SilentlyContinue)) {
        $script:DetectionContract = [ordered]@{
        ValidDetectionSeverities = @('informational', 'low', 'medium', 'high')
        ValidDetectionStatuses   = @('enabled', 'disabled')
        ValidDetectionTactics    = @(
            'Reconnaissance', 'ResourceDevelopment', 'InitialAccess', 'Execution', 'Persistence',
            'PrivilegeEscalation', 'DefenseEvasion', 'CredentialAccess', 'Discovery', 'LateralMovement',
            'Collection', 'CommandAndControl', 'Exfiltration', 'Impact'
        )
        # Rule frequencies the service runs, as whole hours.
        ValidDetectionFrequencyHours = @(1, 3, 12, 24)

        EntityMappingCollections = @(
            'accounts', 'amazonResources', 'azureResources', 'cloudApplications', 'dns', 'files',
            'googleCloudResources', 'hosts', 'ips', 'mailboxes', 'mailClusters', 'mailMessages',
            'oAuthApplications', 'processes', 'registryValues', 'securityGroups', 'urls'
        )

        # automatedActions member -> the column properties every entry needs.
        AutomatedActionRequiredColumns = @{
            allowFiles                   = @()
            blockFiles                   = @()
            collectInvestigationPackages = @('deviceIdColumn')
            disableUsers                 = @('accountSidColumn')
            forceUserPasswordResets      = @('accountSidColumn')
            hardDeleteEmails             = @('networkMessageIdColumn', 'recipientColumn')
            initiateInvestigations       = @('deviceIdColumn')
            isolateDevices               = @('deviceIdColumn', 'isolationType')
            markUsersAsCompromised       = @('accountObjectIdColumn')
            moveEmailsToDeletedItems     = @('networkMessageIdColumn', 'recipientColumn')
            moveEmailsToInbox            = @('networkMessageIdColumn', 'recipientColumn')
            moveEmailsToJunk             = @('networkMessageIdColumn', 'recipientColumn')
            restrictAppExecutions        = @('deviceIdColumn')
            runAntivirusScans            = @('deviceIdColumn')
            softDeleteEmails             = @('networkMessageIdColumn', 'recipientColumn')
            stopAndQuarantineFiles       = @('deviceIdColumn', 'sha1Column')
        }

        # Old responseActions @odata.type -> new automatedActions member and the
        # column property its single identifier fills.
        LegacyResponseActionMap = @{
            markUserAsCompromisedResponseAction       = @{ Member = 'markUsersAsCompromised';       Column = 'accountObjectIdColumn' }
            forceUserPasswordResetResponseAction      = @{ Member = 'forceUserPasswordResets';      Column = 'accountSidColumn' }
            disableUserResponseAction                 = @{ Member = 'disableUsers';                 Column = 'accountSidColumn' }
            collectInvestigationPackageResponseAction = @{ Member = 'collectInvestigationPackages'; Column = 'deviceIdColumn' }
            runAntivirusScanResponseAction            = @{ Member = 'runAntivirusScans';            Column = 'deviceIdColumn' }
            initiateInvestigationResponseAction       = @{ Member = 'initiateInvestigations';       Column = 'deviceIdColumn' }
            restrictAppExecutionResponseAction        = @{ Member = 'restrictAppExecutions';        Column = 'deviceIdColumn' }
            isolateDeviceResponseAction               = @{ Member = 'isolateDevices';               Column = 'deviceIdColumn' }
            hardDeleteResponseAction                  = @{ Member = 'hardDeleteEmails';             Column = $null }
            softDeleteResponseAction                  = @{ Member = 'softDeleteEmails';             Column = $null }
            moveToJunkResponseAction                  = @{ Member = 'moveEmailsToJunk';             Column = $null }
            moveToInboxResponseAction                 = @{ Member = 'moveEmailsToInbox';            Column = $null }
            moveToDeletedItemsResponseAction          = @{ Member = 'moveEmailsToDeletedItems';     Column = $null }
            stopAndQuarantineFileResponseAction       = @{ Member = 'stopAndQuarantineFiles';       Column = $null }
            blockFileResponseAction                   = @{ Member = 'blockFiles';                   Column = $null }
            allowFileResponseAction                   = @{ Member = 'allowFiles';                   Column = $null }
        }

        # Identifier tokens that name a specific column property when an old action
        # carried several comma-separated identifiers.
        LegacyMultiIdentifierColumns = @{
            networkMessageId      = 'networkMessageIdColumn'
            recipientEmailAddress = 'recipientColumn'
            deviceId              = 'deviceIdColumn'
            sha1                  = 'sha1Column'
            sha256                = 'sha256Column'
        }
        }
    }
    return $script:DetectionContract
}

# ---------------------------------------------------------------------------
# Helper: identifier token (accountObjectId) -> query column name (AccountObjectId)
# ---------------------------------------------------------------------------
function ConvertTo-DetectionColumnName {
    param([Parameter(Mandatory = $true)] [string]$Identifier)

    $token = $Identifier.Trim()
    switch ($token) {
        'sha1'   { return 'SHA1' }
        'sha256' { return 'SHA256' }
    }
    return ($token.Substring(0, 1).ToUpperInvariant() + $token.Substring(1))
}

# ---------------------------------------------------------------------------
# Helper: frequency (ISO 8601) or legacy period (1H) -> canonical ISO duration
# ---------------------------------------------------------------------------
# Returns $null when the value is not a frequency the service runs. The
# canonical form is what XmlConvert writes, so PT24H and P1D both become P1D.
function ConvertTo-DetectionFrequency {
    param([AllowNull()] [string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    $text = $Value.Trim().ToUpperInvariant()
    if ($text -match '^(\d+)H$') { $text = "PT$($Matches[1])H" }

    try { $span = [System.Xml.XmlConvert]::ToTimeSpan($text) }
    catch { return $null }

    if ($span.TotalHours -notin (Get-DetectionContract).ValidDetectionFrequencyHours) { return $null }
    return [System.Xml.XmlConvert]::ToString($span)
}

# ---------------------------------------------------------------------------
# Legacy shape translation
# ---------------------------------------------------------------------------
function ConvertTo-DetectionTactic {
    <#
    .SYNOPSIS
        Builds alertTemplate.tactics from a legacy category and mitreTechniques list.
    .DESCRIPTION
        Sub-techniques (T1110.003) are grouped under their parent technique
        (T1110), in the order the techniques first appear.
    #>
    param(
        [Parameter(Mandatory = $true)] [string]$Category
        ,
        [AllowNull()] [object[]]$MitreTechniques
    )

    $techniques = [ordered]@{}
    foreach ($raw in @($MitreTechniques)) {
        if ([string]::IsNullOrWhiteSpace([string]$raw)) { continue }
        $id = ([string]$raw).Trim()
        $parent = ($id -split '\.')[0]
        if (-not $techniques.Contains($parent)) {
            $techniques[$parent] = [System.Collections.Generic.List[string]]::new()
        }
        if ($id -ne $parent -and -not $techniques[$parent].Contains($id)) {
            $techniques[$parent].Add($id)
        }
    }

    $tactic = [ordered]@{ tactic = $Category }
    if ($techniques.Count -gt 0) {
        $tactic['techniques'] = @($techniques.Keys | ForEach-Object {
            $entry = [ordered]@{ technique = $_ }
            if ($techniques[$_].Count -gt 0) { $entry['subTechniques'] = @($techniques[$_]) }
            $entry
        })
    }
    return , @($tactic)
}

function ConvertTo-DetectionEntityMapping {
    <#
    .SYNOPSIS
        Builds alertTemplate.entityMappings from legacy impactedAssets.
    .DESCRIPTION
        Each impacted asset becomes one mapping in the matching collection
        (accounts, hosts, mailboxes). Its identifier token names the query
        column, and the token's suffix picks the column property: ObjectId
        maps to aadUserIdColumn, Sid to sidColumn, Upn to upnColumn, Name to
        nameColumn, Domain to ntDomainColumn, a device Id to deviceIdColumn,
        and a mailbox Address to primaryAddressColumn. A token that fits none
        of these throws, so nothing is guessed.
    #>
    param([AllowNull()] [object[]]$ImpactedAssets)

    $mappings = [ordered]@{}
    foreach ($asset in @($ImpactedAssets)) {
        if ($null -eq $asset) { continue }
        $type       = ([string]$asset['@odata.type']) -replace '^#?microsoft\.graph\.security\.', ''
        $identifier = [string]$asset['identifier']
        $column     = ConvertTo-DetectionColumnName -Identifier $identifier

        switch ($type) {
            'impactedUserAsset' {
                $collection = 'accounts'
                $property = switch -Regex ($identifier) {
                    'ObjectId$' { 'aadUserIdColumn'; break }
                    'Sid$'      { 'sidColumn'; break }
                    'Upn$'      { 'upnColumn'; break }
                    'Name$'     { 'nameColumn'; break }
                    'Domain$'   { 'ntDomainColumn'; break }
                    default     { throw "impactedUserAsset identifier '$identifier' has no account entity column property." }
                }
            }
            'impactedDeviceAsset' {
                $collection = 'hosts'
                $property = switch -Regex ($identifier) {
                    'Id$'   { 'deviceIdColumn'; break }
                    'Name$' { 'nameColumn'; break }
                    default { throw "impactedDeviceAsset identifier '$identifier' has no host entity column property." }
                }
            }
            'impactedMailboxAsset' {
                $collection = 'mailboxes'
                if ($identifier -notmatch 'Address$') {
                    throw "impactedMailboxAsset identifier '$identifier' has no mailbox entity column property."
                }
                $property = 'primaryAddressColumn'
            }
            default { throw "Unknown impactedAssets type '$type'." }
        }

        if (-not $mappings.Contains($collection)) {
            $mappings[$collection] = [System.Collections.Generic.List[object]]::new()
        }
        $mappings[$collection].Add([ordered]@{ $property = $column })
    }

    $result = [ordered]@{}
    foreach ($key in $mappings.Keys) { $result[$key] = @($mappings[$key]) }
    return $result
}

function ConvertTo-DetectionAutomatedAction {
    <#
    .SYNOPSIS
        Builds detectionAction.automatedActions from legacy responseActions.
    #>
    param([AllowNull()] [object[]]$ResponseActions)

    $actions = [ordered]@{}
    foreach ($action in @($ResponseActions)) {
        if ($null -eq $action) { continue }
        $type = ([string]$action['@odata.type']) -replace '^#?microsoft\.graph\.security\.', ''
        if (-not (Get-DetectionContract).LegacyResponseActionMap.ContainsKey($type)) {
            throw "Unknown responseActions type '$type'."
        }
        $target = (Get-DetectionContract).LegacyResponseActionMap[$type]
        $entry  = [ordered]@{}

        $tokens = @(([string]$action['identifier']) -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        if ($target.Column -and $tokens.Count -eq 1) {
            $entry[$target.Column] = ConvertTo-DetectionColumnName -Identifier $tokens[0]
        }
        else {
            foreach ($token in $tokens) {
                if (-not (Get-DetectionContract).LegacyMultiIdentifierColumns.ContainsKey($token)) {
                    throw "responseActions '$type' identifier '$token' has no automated action column property."
                }
                $entry[(Get-DetectionContract).LegacyMultiIdentifierColumns[$token]] = ConvertTo-DetectionColumnName -Identifier $token
            }
        }
        if ($action.Contains('isolationType')) { $entry['isolationType'] = [string]$action['isolationType'] }
        if ($action.Contains('deviceGroupNames')) { $entry['deviceGroupNames'] = @($action['deviceGroupNames']) }

        if (-not $actions.Contains($target.Member)) {
            $actions[$target.Member] = [System.Collections.Generic.List[object]]::new()
        }
        $actions[$target.Member].Add($entry)
    }

    $result = [ordered]@{}
    foreach ($key in $actions.Keys) { $result[$key] = @($actions[$key]) }
    return $result
}

function ConvertFrom-LegacyDetectionRule {
    <#
    .SYNOPSIS
        Translates a rule written with the pre-2026-10-01 Graph field names
        into the current shape.
    .DESCRIPTION
        Returns @{ Rule = <rule in the current shape>; LegacyFields = <names
        of the legacy fields that were translated> }. A rule already in the
        current shape comes back unchanged with no legacy fields. Where a
        rule sets both an old field and its replacement, the replacement
        wins and the old field is dropped.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Rule
    )

    $legacy = [System.Collections.Generic.List[string]]::new()
    $out = [ordered]@{}
    foreach ($key in $Rule.Keys) { $out[$key] = $Rule[$key] }

    if ($out.Contains('isEnabled')) {
        if (-not $out.Contains('status')) { $out['status'] = if ([bool]$out['isEnabled']) { 'enabled' } else { 'disabled' } }
        $out.Remove('isEnabled')
        $legacy.Add('isEnabled')
    }
    if ($out.Contains('lastModifiedDateTime')) {
        $out.Remove('lastModifiedDateTime')
        $legacy.Add('lastModifiedDateTime')
    }

    if ($out['queryCondition'] -is [System.Collections.IDictionary] -and $out['queryCondition'].Contains('lastModifiedDateTime')) {
        $query = [ordered]@{}
        foreach ($key in $out['queryCondition'].Keys) { if ($key -ne 'lastModifiedDateTime') { $query[$key] = $out['queryCondition'][$key] } }
        $out['queryCondition'] = $query
        $legacy.Add('queryCondition.lastModifiedDateTime')
    }

    if ($out['schedule'] -is [System.Collections.IDictionary] -and $out['schedule'].Contains('period')) {
        $schedule = [ordered]@{}
        foreach ($key in $out['schedule'].Keys) { if ($key -ne 'period') { $schedule[$key] = $out['schedule'][$key] } }
        if (-not $schedule.Contains('frequency')) {
            $frequency = ConvertTo-DetectionFrequency -Value ([string]$out['schedule']['period'])
            $schedule['frequency'] = if ($frequency) { $frequency } else { [string]$out['schedule']['period'] }
        }
        $out['schedule'] = $schedule
        $legacy.Add('schedule.period')
    }

    if ($out['detectionAction'] -is [System.Collections.IDictionary]) {
        $action = [ordered]@{}
        foreach ($key in $out['detectionAction'].Keys) { $action[$key] = $out['detectionAction'][$key] }

        if ($action['alertTemplate'] -is [System.Collections.IDictionary]) {
            $template = [ordered]@{}
            foreach ($key in $action['alertTemplate'].Keys) { $template[$key] = $action['alertTemplate'][$key] }

            if ($template.Contains('category') -or $template.Contains('mitreTechniques')) {
                if (-not $template.Contains('tactics') -and $template.Contains('category')) {
                    $template['tactics'] = ConvertTo-DetectionTactic -Category ([string]$template['category']) -MitreTechniques @($template['mitreTechniques'])
                }
                foreach ($old in 'category', 'mitreTechniques') {
                    if ($template.Contains($old)) { $template.Remove($old); $legacy.Add("alertTemplate.$old") }
                }
            }
            if ($template.Contains('impactedAssets')) {
                if (-not $template.Contains('entityMappings')) {
                    $template['entityMappings'] = ConvertTo-DetectionEntityMapping -ImpactedAssets @($template['impactedAssets'])
                }
                $template.Remove('impactedAssets')
                $legacy.Add('alertTemplate.impactedAssets')
            }
            $action['alertTemplate'] = $template
        }

        if ($action.Contains('responseActions')) {
            if (-not $action.Contains('automatedActions')) {
                $action['automatedActions'] = ConvertTo-DetectionAutomatedAction -ResponseActions @($action['responseActions'])
            }
            $action.Remove('responseActions')
            $legacy.Add('detectionAction.responseActions')
        }

        if ($action['organizationalScope'] -is [System.Collections.IDictionary] -and $action['organizationalScope'].Contains('scopeNames')) {
            if (-not $action['organizationalScope'].Contains('deviceGroups')) {
                $action['organizationalScope'] = [ordered]@{ deviceGroups = @($action['organizationalScope']['scopeNames']) }
            }
            else {
                $action['organizationalScope'] = [ordered]@{ deviceGroups = @($action['organizationalScope']['deviceGroups']) }
            }
            $legacy.Add('organizationalScope.scopeNames')
        }

        $out['detectionAction'] = $action
    }

    return @{ Rule = $out; LegacyFields = @($legacy) }
}

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------
function Test-DetectionRule {
    <#
    .SYNOPSIS
        Returns the problems that would stop a rule (in the current shape)
        from deploying. An empty result means the rule is valid.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Rule
    )

    $issues = [System.Collections.Generic.List[string]]::new()

    if ([string]::IsNullOrWhiteSpace([string]$Rule['displayName'])) { $issues.Add("missing required field 'displayName'") }

    if (-not ($Rule['queryCondition'] -is [System.Collections.IDictionary]) -or [string]::IsNullOrWhiteSpace([string]$Rule['queryCondition']['queryText'])) {
        $issues.Add("missing required field 'queryCondition.queryText'")
    }

    if (-not ($Rule['schedule'] -is [System.Collections.IDictionary]) -or [string]::IsNullOrWhiteSpace([string]$Rule['schedule']['frequency'])) {
        $issues.Add("missing required field 'schedule.frequency'")
    }
    elseif (-not (ConvertTo-DetectionFrequency -Value ([string]$Rule['schedule']['frequency']))) {
        $issues.Add("invalid schedule.frequency '$($Rule['schedule']['frequency'])'; use PT1H, PT3H, PT12H or P1D")
    }

    if ($Rule.Contains('status') -and ([string]$Rule['status']) -notin (Get-DetectionContract).ValidDetectionStatuses) {
        $issues.Add("invalid status '$($Rule['status'])'; use $((Get-DetectionContract).ValidDetectionStatuses -join ' or ')")
    }

    $action = $Rule['detectionAction']
    $template = if ($action -is [System.Collections.IDictionary]) { $action['alertTemplate'] } else { $null }
    if (-not ($template -is [System.Collections.IDictionary])) {
        $issues.Add("missing required field 'detectionAction.alertTemplate'")
        return $issues.ToArray()
    }

    foreach ($field in 'title', 'severity') {
        if ([string]::IsNullOrWhiteSpace([string]$template[$field])) { $issues.Add("alertTemplate missing required field '$field'") }
    }
    if ($template['severity'] -and ([string]$template['severity']) -notin (Get-DetectionContract).ValidDetectionSeverities) {
        $issues.Add("invalid alertTemplate.severity '$($template['severity'])'; use $((Get-DetectionContract).ValidDetectionSeverities -join ', ')")
    }

    $tactics = @($template['tactics'] | Where-Object { $null -ne $_ })
    if ($tactics.Count -eq 0) {
        $issues.Add("alertTemplate missing required field 'tactics'")
    }
    foreach ($tactic in $tactics) {
        if (-not ($tactic -is [System.Collections.IDictionary]) -or ([string]$tactic['tactic']) -notin (Get-DetectionContract).ValidDetectionTactics) {
            $name = if ($tactic -is [System.Collections.IDictionary]) { $tactic['tactic'] } else { $tactic }
            $issues.Add("unknown tactic '$name'")
            continue
        }
        foreach ($technique in @($tactic['techniques'] | Where-Object { $null -ne $_ })) {
            $parent = [string]$technique['technique']
            if ($parent -notmatch '^T\d{4}(\.\d{3})?$') { $issues.Add("invalid technique '$parent' under $($tactic['tactic'])") }
            foreach ($sub in @($technique['subTechniques'] | Where-Object { $null -ne $_ })) {
                if ([string]$sub -notmatch "^$([regex]::Escape($parent))\.\d{3}$") { $issues.Add("sub-technique '$sub' does not belong to $parent") }
            }
        }
    }

    if ($template['entityMappings'] -is [System.Collections.IDictionary]) {
        foreach ($collection in $template['entityMappings'].Keys) {
            if ($collection -notin (Get-DetectionContract).EntityMappingCollections) { $issues.Add("unknown entityMappings collection '$collection'") }
        }
    }

    if ($action['automatedActions'] -is [System.Collections.IDictionary]) {
        foreach ($member in $action['automatedActions'].Keys) {
            if (-not (Get-DetectionContract).AutomatedActionRequiredColumns.ContainsKey($member)) {
                $issues.Add("unknown automatedActions member '$member'")
                continue
            }
            foreach ($entry in @($action['automatedActions'][$member])) {
                foreach ($required in (Get-DetectionContract).AutomatedActionRequiredColumns[$member]) {
                    if (-not ($entry -is [System.Collections.IDictionary]) -or [string]::IsNullOrWhiteSpace([string]$entry[$required])) {
                        $issues.Add("automatedActions.$member entry missing '$required'")
                    }
                }
            }
        }
    }

    return $issues.ToArray()
}

# ---------------------------------------------------------------------------
# Helper: query columns a rule's mappings and actions depend on
# ---------------------------------------------------------------------------
function Get-DetectionMappedColumn {
    <#
    .SYNOPSIS
        Returns the distinct query result columns named by a rule's entity
        mappings, automated actions and custom details.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Rule
    )

    $columns = [System.Collections.Generic.List[string]]::new()
    $action = $Rule['detectionAction']
    $template = if ($action -is [System.Collections.IDictionary]) { $action['alertTemplate'] } else { $null }

    $collections = @()
    if ($template -is [System.Collections.IDictionary] -and $template['entityMappings'] -is [System.Collections.IDictionary]) {
        $collections += @($template['entityMappings'].Values)
    }
    if ($action -is [System.Collections.IDictionary] -and $action['automatedActions'] -is [System.Collections.IDictionary]) {
        $collections += @($action['automatedActions'].Values)
    }
    foreach ($entry in @($collections | ForEach-Object { $_ })) {
        if (-not ($entry -is [System.Collections.IDictionary])) { continue }
        foreach ($key in $entry.Keys) {
            if ($key -like '*Column' -and -not [string]::IsNullOrWhiteSpace([string]$entry[$key])) { $columns.Add([string]$entry[$key]) }
        }
    }
    if ($template -is [System.Collections.IDictionary] -and $template['customDetails'] -is [System.Collections.IDictionary]) {
        foreach ($value in $template['customDetails'].Values) { if ($value) { $columns.Add([string]$value) } }
    }

    return @($columns | Select-Object -Unique)
}

# ---------------------------------------------------------------------------
# Convert a rule (current shape) to the Graph API request body
# ---------------------------------------------------------------------------
function ConvertTo-GraphDetectionBody {
    <#
    .SYNOPSIS
        Builds the Graph detectionRule request body from a rule in the
        current shape.
    .DESCRIPTION
        -ForCreate adds the client-provided rule id, which Graph requires
        when a rule is created and does not accept on update.
        organizationalScope is sent as null unless the rule sets device
        groups, and automatedActions as an empty set unless the rule sets
        some, so the repo file stays the source of truth on update.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Rule
        ,
        [switch]$ForCreate
    )

    $source = $Rule['detectionAction']['alertTemplate']
    $alertTemplate = [ordered]@{
        title    = [string]$source['title']
        severity = ([string]$source['severity']).ToLowerInvariant()
        tactics  = @($source['tactics'])
    }
    foreach ($optional in 'description', 'recommendedActions', 'entityMappings', 'customDetails') {
        if ($source.Contains($optional) -and $null -ne $source[$optional]) { $alertTemplate[$optional] = $source[$optional] }
    }

    $sourceAction = $Rule['detectionAction']
    $detectionAction = [ordered]@{
        alertTemplate       = $alertTemplate
        automatedActions    = if ($sourceAction['automatedActions'] -is [System.Collections.IDictionary]) { $sourceAction['automatedActions'] } else { @{} }
        organizationalScope = $null
    }
    if ($sourceAction['organizationalScope'] -is [System.Collections.IDictionary] -and @($sourceAction['organizationalScope']['deviceGroups']).Count -gt 0) {
        $detectionAction.organizationalScope = [ordered]@{ deviceGroups = @($sourceAction['organizationalScope']['deviceGroups']) }
    }
    if ($sourceAction['incidentConfiguration'] -is [System.Collections.IDictionary]) {
        $detectionAction.incidentConfiguration = $sourceAction['incidentConfiguration']
    }

    $body = [ordered]@{}
    if ($ForCreate) { $body.id = [string]$Rule['id'] }
    $body.displayName     = [string]$Rule['displayName']
    $body.status          = if ($Rule.Contains('status') -and $Rule['status']) { [string]$Rule['status'] } else { 'enabled' }
    if ($Rule.Contains('description') -and $Rule['description']) { $body.description = [string]$Rule['description'] }
    $body.queryCondition  = [ordered]@{ queryText = [string]$Rule['queryCondition']['queryText'] }
    $body.schedule        = [ordered]@{ frequency = ConvertTo-DetectionFrequency -Value ([string]$Rule['schedule']['frequency']) }
    $body.detectionAction = $detectionAction

    return $body
}

# ---------------------------------------------------------------------------
# Deploy Custom Detection Rules
# ---------------------------------------------------------------------------
function Deploy-DefenderDetections {
    [CmdletBinding()]
    param()

    $counters = @{ Created = 0; Updated = 0; Skipped = 0; Failed = 0 }
    $detectionsPath = Join-Path $BasePath "Content" "DefenderCustomDetections"

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
        $body = $null
        try {
            $yamlContent = Get-Content -Path $file.FullName -Raw
            $rule = ConvertFrom-Yaml -Yaml $yamlContent

            # Rules written with the field names Graph removed on 2026-10-01
            # still deploy: they are translated to the current shape first.
            $translated = ConvertFrom-LegacyDetectionRule -Rule $rule
            $rule = $translated.Rule
            if ($translated.LegacyFields.Count -gt 0) {
                Write-PipelineMessage "'$($file.Name)' uses retired Graph fields ($($translated.LegacyFields -join ', ')); deploying a translated copy. Convert the file to the current shape (see Docs/Content/Defender-Custom-Detections.md)." -Level Warning
            }

            $issues = @(Test-DetectionRule -Rule $rule)
            if ($issues.Count -gt 0) {
                Write-PipelineMessage "Skipping '$($file.Name)': $($issues -join '; ')." -Level Warning
                $counters.Skipped++
                continue
            }

            $ruleName  = [string]$rule['displayName']
            $frequency = ConvertTo-DetectionFrequency -Value ([string]$rule['schedule']['frequency'])
            $severity  = [string]$rule['detectionAction']['alertTemplate']['severity']

            Write-PipelineMessage "Processing: $ruleName (every $frequency) [$($file.Name)]" -Level Info

            if ($WhatIf) {
                $body = ConvertTo-GraphDetectionBody -Rule $rule | ConvertTo-Json -Depth 20
                Write-PipelineMessage "[WhatIf] Would deploy detection: $ruleName (Schedule: $frequency, Severity: $severity)" -Level Info
                $counters.Created++
            }
            # Existing rules are matched by displayName and updated in place;
            # their id was set when they were created and cannot change.
            elseif ($existingRuleMap.ContainsKey($ruleName)) {
                $existingId = $existingRuleMap[$ruleName]
                $body = ConvertTo-GraphDetectionBody -Rule $rule | ConvertTo-Json -Depth 20
                $uri = "$($script:DetectionRulesEndpoint)/$existingId"
                Invoke-GraphApi -Uri $uri -Method Patch -Headers $script:GraphAuthHeader -Body $body | Out-Null
                Write-PipelineMessage "Updated: $ruleName (ID: $existingId)" -Level Success
                $counters.Updated++
            }
            # Graph requires a client-provided id to create a rule.
            elseif ([string]::IsNullOrWhiteSpace([string]$rule['id'])) {
                Write-PipelineMessage "Failed to deploy '$($file.Name)': '$ruleName' does not exist yet and the file has no 'id'; Graph needs a client-provided id to create a rule." -Level Error
                $counters.Failed++
            }
            else {
                $body = ConvertTo-GraphDetectionBody -Rule $rule -ForCreate | ConvertTo-Json -Depth 20
                $result = Invoke-GraphApi -Uri $script:DetectionRulesEndpoint -Method Post -Headers $script:GraphAuthHeader -Body $body
                Write-PipelineMessage "Created: $ruleName (ID: $($result.id))" -Level Success
                $counters.Created++
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
# Entry point
# ---------------------------------------------------------------------------
function Invoke-Main {
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

Invoke-Main

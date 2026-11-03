#Requires -Version 7.2
#Requires -Modules Az.Accounts, Az.Resources

<#
.SYNOPSIS
    Exports Logic App playbooks from Azure as parameterised ARM templates
    in the Content/Playbooks/ shape that Deploy-CustomContent.ps1 deploys

.DESCRIPTION
    Reads every Logic App in the playbook resource group, works out each
    one's trigger type from its workflow definition (Incident, Entity,
    Alert, Module, Watchlist or Other) and writes a parameterised ARM
    template to:

        Content/Playbooks/<Category>/<Name>.json

    The output follows the repo's playbook conventions, so a round trip
    (export, commit, redeploy) lands on the same Azure resources:

      - The file name drops any leading category prefix, so the Logic
        App Module-AddSentinelComment becomes
        Module/AddSentinelComment.json. The PlaybookName default keeps the
        live Logic App name, so a redeploy updates the existing workflow
        rather than creating a second one.
      - Hardcoded subscription IDs, resource-group names, the workspace
        name and the workspace ID are replaced with ARM expressions:
        subscription().subscriptionId and the parameters that
        Deploy-CustomContent.ps1 injects (AutomationResourceGroup,
        SentinelResourceGroupName, SentinelWorkpaceName, WorkspaceId).
        Every parameter an expression references is declared.
      - Each API connection becomes a Microsoft.Web/connections resource
        named after the playbook. Connections that use a managed identity
        keep it. Connections that use OAuth or an API key are written
        without one and need a one-time authorisation after deployment.
      - The workflow keeps its live state (Enabled or Disabled), carries
        the Source: Sentinel-As-Code tag that Set-PlaybookPermissions.ps1
        keys off, and gets the metadata block the docs describe (title,
        description, entities, tags, support, author).

    A workflow can hold secrets in plain text, such as an API key in an
    HTTP header, a client secret in an authentication block, or a
    function key in a URI. The export does not remove them. It reports
    each one it finds as a warning so it can be moved to Key Vault before
    the template is committed.

    Existing files are skipped unless -Force is passed. -WhatIf reads
    everything from Azure and writes nothing.

.PARAMETER SubscriptionId
    Azure subscription ID. Defaults to the current Az context.

.PARAMETER ResourceGroup
    Resource group containing the Sentinel workspace. Hardcoded
    references to it are replaced with the SentinelResourceGroupName
    parameter.

.PARAMETER Workspace
    Log Analytics workspace name. Hardcoded references to it, and to its
    workspace ID, are replaced with the SentinelWorkpaceName and
    WorkspaceId parameters.

.PARAMETER Region
    Azure region. Required by Connect-AzureEnvironment but not used for
    export, since Logic Apps are listed by resource group.

.PARAMETER PlaybookResourceGroup
    Resource group holding the Logic Apps. Defaults to -ResourceGroup.
    Hardcoded references to it are replaced with the
    AutomationResourceGroup parameter.

.PARAMETER OutputPath
    Folder the category subfolders are written under. Defaults to
    Content/Playbooks under the repository root.

.PARAMETER NameFilter
    Optional wildcard applied to Logic App names, for example 'Module-*'
    or '*Defender*'. Logic Apps that do not match are skipped.

.PARAMETER Author
    Author name written to each template's metadata block. Defaults to
    'noodlemctwoodle'.

.PARAMETER Force
    Overwrite templates that already exist. Without it, existing files
    are left alone and reported as skipped.

.PARAMETER IsGov
    Target the Azure Government cloud.

.EXAMPLE
    ./Tools/Export-Playbooks.ps1 `
        -ResourceGroup         'rg-sentinel-prod' `
        -Workspace             'law-sentinel-prod' `
        -Region                'uksouth' `
        -PlaybookResourceGroup 'rg-sentinel-automation'

    Exports every Logic App in rg-sentinel-automation that does not
    already have a template under Content/Playbooks/.

.EXAMPLE
    ./Tools/Export-Playbooks.ps1 `
        -ResourceGroup 'rg-sentinel-prod' `
        -Workspace     'law-sentinel-prod' `
        -Region        'uksouth' `
        -NameFilter    'Module-*' `
        -Force

    Exports only the Module playbooks from the workspace resource group,
    overwriting any templates already in the repo.

.EXAMPLE
    ./Tools/Export-Playbooks.ps1 `
        -ResourceGroup 'rg-sentinel-prod' `
        -Workspace     'law-sentinel-prod' `
        -Region        'uksouth' `
        -OutputPath    './export' `
        -WhatIf

    Reads every Logic App and reports what would be written under
    ./export, without writing anything.

.NOTES
    File:         Tools/Export-Playbooks.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-03-24
    Version:      2.0.0
    Last Updated: 2026-10-15
    Requires:     PowerShell 7.2+, Az.Accounts, Az.Resources, Sentinel.Common module

    API versions:
      - Logic Apps workflows      : 2019-05-01 (read)
      - Template workflow resource: 2017-07-01 (matches the existing
                                    Content/Playbooks templates)
      - Template connections      : 2016-06-01 (matches the existing
                                    Content/Playbooks templates)

    Az.Resources is needed because Connect-AzureEnvironment checks that
    -PlaybookResourceGroup exists when it differs from -ResourceGroup.

.LINK
    https://learn.microsoft.com/rest/api/logic/workflows/list-by-resource-group

.LINK
    https://learn.microsoft.com/azure/azure-resource-manager/templates/template-expressions
#>

[CmdletBinding(SupportsShouldProcess)]
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
    [string]$PlaybookResourceGroup
    ,
    [Parameter(Mandatory = $false)]
    [string]$OutputPath
    ,
    [Parameter(Mandatory = $false)]
    [string]$NameFilter
    ,
    [Parameter(Mandatory = $false)]
    [string]$Author = 'noodlemctwoodle'
    ,
    [Parameter(Mandatory = $false)]
    [switch]$Force
    ,
    [Parameter(Mandatory = $false)]
    [switch]$IsGov
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '../Modules/Sentinel.Common/Sentinel.Common.psd1') -Force -ErrorAction Stop

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
$script:LogicAppApiVersion   = '2019-05-01'
$script:WorkflowApiVersion   = '2017-07-01'
$script:ConnectionApiVersion = '2016-06-01'

if (-not $OutputPath) {
    $OutputPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'Content/Playbooks'
}
$OutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)

# ---------------------------------------------------------------------------
# Object helpers
# ---------------------------------------------------------------------------
function Get-SafeProperty {
    param($Object, [string]$Name)

    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $null
    }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -ne $prop) { return $prop.Value }
    return $null
}

function Get-PropertyNames {
    param($Object)

    if ($null -eq $Object -or $Object -is [string]) { return [string[]]@() }
    if ($Object -is [System.Collections.IDictionary]) { return [string[]]@($Object.Keys) }
    return [string[]]@($Object.PSObject.Properties | ForEach-Object { $_.Name })
}

# ---------------------------------------------------------------------------
# Classification
# ---------------------------------------------------------------------------
function Get-TriggerCategory {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] $Definition
    )

    $triggers = Get-SafeProperty $Definition 'triggers'
    foreach ($triggerName in @(Get-PropertyNames $triggers)) {
        $trigger     = Get-SafeProperty $triggers $triggerName
        $triggerType = Get-SafeProperty $trigger 'type'
        $triggerKind = Get-SafeProperty $trigger 'kind'
        $path        = Get-SafeProperty (Get-SafeProperty $trigger 'inputs') 'path'

        if ($triggerType -eq 'ApiConnectionWebhook') {
            if ($path -match '/incident-creation') { return 'Incident' }
            if ($path -match '/entity/')           { return 'Entity' }
            if ($path -match '/subscribe')         { return 'Alert' }
        }

        if ($triggerType -eq 'Request' -and $triggerKind -eq 'Http') {
            return 'Module'
        }

        if ($triggerType -eq 'ApiConnection' -and $path -match '/watchlist') {
            return 'Watchlist'
        }
    }

    $actions = Get-SafeProperty $Definition 'actions'
    if ($actions) {
        $actionsJson = $actions | ConvertTo-Json -Depth 100 -Compress
        if ($actionsJson -match 'watchlist') { return 'Watchlist' }
    }

    return 'Other'
}

function Get-PlaybookFileName {
    <#
    .SYNOPSIS
        Returns the template file name (without extension) for a Logic App,
        dropping a leading category prefix to match Content/Playbooks/.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string]$LogicAppName
    )

    foreach ($prefix in @('Incident', 'Entity', 'Alert', 'Module', 'Watchlist', 'Other')) {
        $withDash = "$prefix-"
        if ($LogicAppName.Length -gt $withDash.Length -and
            $LogicAppName.StartsWith($withDash, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $LogicAppName.Substring($withDash.Length)
        }
    }
    return $LogicAppName
}

function Get-WorkflowEntities {
    <#
    .SYNOPSIS
        Returns the Sentinel entity types a workflow operates on.
    .DESCRIPTION
        Scans the definition for entity trigger paths (/entity/{type}),
        entity action paths (/entities/{type}) and the portal's default
        action names (Entities_-_Get_IPs and so on), then maps each match
        to its Sentinel entity type name.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Definition
    )

    $entityMap = @{
        'ip'       = 'IP'
        'host'     = 'Host'
        'account'  = 'Account'
        'filehash' = 'FileHash'
        'url'      = 'URL'
        'file'     = 'File'
        'dns'      = 'DNS'
        'process'  = 'Process'
        'malware'  = 'Malware'
        'registry' = 'RegistryKey'
    }

    $json = $Definition | ConvertTo-Json -Depth 100 -Compress

    $candidates = [System.Collections.Generic.List[string]]::new()
    foreach ($m in [regex]::Matches($json, "/entit(?:y|ies)/(?:@\{encodeURIComponent\(')?([A-Za-z]+)")) {
        $candidates.Add($m.Groups[1].Value)
    }
    foreach ($m in [regex]::Matches($json, 'Entities_-_Get_([A-Za-z]+)')) {
        $candidates.Add($m.Groups[1].Value)
    }

    $found = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($raw in $candidates) {
        $key = $raw.ToLowerInvariant()
        # Try the word as-is, then without a plural "es", then without a
        # plural "s", so DNS stays DNS while FileHashes and IPs singularise.
        $match = @($key, ($key -replace 'es$', ''), ($key -replace 's$', '')) |
            Where-Object { $entityMap.ContainsKey($_) } |
            Select-Object -First 1
        if ($match) { [void]$found.Add($entityMap[$match]) }
    }

    return @($found | Sort-Object)
}

function Get-WorkflowDescription {
    <#
    .SYNOPSIS
        Returns the workflow's own description, or builds one from its
        category and entities.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] $LogicApp,
        [Parameter(Mandatory)] [string]$Category,
        [Parameter(Mandatory)] [string]$PlaybookName,
        [string[]]$Entities = @()
    )

    $properties = Get-SafeProperty $LogicApp 'properties'
    $desc = Get-SafeProperty (Get-SafeProperty $properties 'definition') 'description'
    if ($desc) { return $desc }

    $desc = Get-SafeProperty $properties 'description'
    if ($desc) { return $desc }

    $entitySuffix = ''
    if ($Entities.Count -gt 0) {
        $entitySuffix = " targeting $($Entities -join ', ') entities"
    }

    switch ($Category) {
        'Incident'  { return "Sentinel incident-trigger playbook for ${PlaybookName}${entitySuffix}." }
        'Entity'    { return "Sentinel entity-trigger playbook for ${PlaybookName}${entitySuffix}." }
        'Alert'     { return "Sentinel alert-trigger playbook for ${PlaybookName}${entitySuffix}." }
        'Module'    { return "Reusable automation module: ${PlaybookName}." }
        'Watchlist' { return "Watchlist management playbook: ${PlaybookName}." }
        default     { return "Automation playbook: ${PlaybookName}." }
    }
}

# ---------------------------------------------------------------------------
# Connections
# ---------------------------------------------------------------------------
function Get-ApiConnectorDisplayName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$ApiName
    )

    $displayMap = @{
        'azuresentinel'                  = 'MicrosoftSentinel'
        'microsoftsentinel'              = 'MicrosoftSentinel'
        'wdatp'                          = 'MicrosoftDefenderXDR'
        'office365'                      = 'Office365'
        'teams'                          = 'MicrosoftTeams'
        'azuread'                        = 'AzureAD'
        'keyvault'                       = 'AzureKeyVault'
        'azureloganalytics'              = 'AzureLogAnalytics'
        'azuremonitorlogs'               = 'AzureMonitorLogs'
        'servicebus'                     = 'AzureServiceBus'
        'azureblob'                      = 'AzureBlobStorage'
        'sharepointonline'               = 'SharePointOnline'
        'cognitiveservicestextanalytics' = 'CognitiveServicesTextAnalytics'
        'microsoftgraphsecurity'         = 'MicrosoftGraphSecurity'
        'arm'                            = 'AzureResourceManager'
    }

    $lower = $ApiName.ToLowerInvariant()
    if ($displayMap.ContainsKey($lower)) { return $displayMap[$lower] }
    return ($ApiName.Substring(0, 1).ToUpperInvariant() + $ApiName.Substring(1))
}

function Get-ConnectionMap {
    <#
    .SYNOPSIS
        Describes each entry in a workflow's $connections parameter value.
    .DESCRIPTION
        Returns an ordered dictionary keyed by the connection reference name
        the workflow uses (azuresentinel, office365-1 and so on). Each entry
        carries the managed API name, the ARM variable name, the connection
        resource name prefix and whether the live connection authenticates
        with the workflow's managed identity.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()] $ConnectionsValue
    )

    $map = [ordered]@{}
    foreach ($connName in @(Get-PropertyNames $ConnectionsValue)) {
        $detail = Get-SafeProperty $ConnectionsValue $connName

        $apiId = if ($detail -is [string]) { $detail } else { Get-SafeProperty $detail 'id' }
        $apiName = if ($apiId -and $apiId -match '/managedApis/([^/]+)$') {
            $Matches[1]
        }
        else {
            # No managed API id: fall back to the reference name minus the
            # portal's numeric suffix (office365-1, virustotal_1).
            $connName -replace '[-_]\d+$', ''
        }

        $authType = Get-SafeProperty (Get-SafeProperty (Get-SafeProperty $detail 'connectionProperties') 'authentication') 'type'
        $map[$connName] = [ordered]@{
            ApiName             = $apiName
            DisplayName         = Get-ApiConnectorDisplayName -ApiName $apiName
            UsesManagedIdentity = ($authType -eq 'ManagedServiceIdentity')
        }
    }

    # Index only the APIs the workflow connects to more than once, so each
    # connection resource name stays unique without turning Office365 into
    # Office3650.
    $totals  = @{}
    foreach ($conn in $map.Values) { $totals[$conn.DisplayName] = 1 + [int]$totals[$conn.DisplayName] }
    $indexes = @{}
    foreach ($conn in $map.Values) {
        $prefix = $conn.DisplayName
        if ($totals[$prefix] -gt 1) {
            $index = [int]$indexes[$prefix]
            $indexes[$prefix] = $index + 1
            $prefix = "$prefix$index"
        }
        $conn['ResourcePrefix'] = $prefix
        $conn['VariableName']   = "${prefix}ConnectionName"
    }

    return $map
}

function Get-ManagedApiIdExpression {
    param([Parameter(Mandatory)] [string]$ApiName)

    return "[concat('/subscriptions/', subscription().subscriptionId, '/providers/Microsoft.Web/locations/', resourceGroup().location, '/managedApis/$ApiName')]"
}

function Build-ConnectionVariables {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [System.Collections.IDictionary]$ConnectionMap
    )

    $variables = [ordered]@{}
    foreach ($conn in $ConnectionMap.Values) {
        $variables[$conn.VariableName] = "[concat('$($conn.ResourcePrefix)-', parameters('PlaybookName'))]"
    }
    return $variables
}

function Build-ConnectionResources {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [System.Collections.IDictionary]$ConnectionMap
    )

    $resources = [System.Collections.Generic.List[object]]::new()
    foreach ($conn in $ConnectionMap.Values) {
        $properties = [ordered]@{
            displayName           = "[variables('$($conn.VariableName)')]"
            customParameterValues = @{}
        }
        if ($conn.UsesManagedIdentity) {
            $properties['parameterValueType'] = 'Alternative'
        }
        $properties['api'] = [ordered]@{ id = Get-ManagedApiIdExpression -ApiName $conn.ApiName }

        $resources.Add([ordered]@{
            type       = 'Microsoft.Web/connections'
            apiVersion = $script:ConnectionApiVersion
            name       = "[variables('$($conn.VariableName)')]"
            location   = '[resourceGroup().location]'
            kind       = 'V1'
            properties = $properties
        })
    }
    return $resources.ToArray()
}

function Build-ConnectionParameters {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [System.Collections.IDictionary]$ConnectionMap
    )

    $values = [ordered]@{}
    foreach ($entry in $ConnectionMap.GetEnumerator()) {
        $conn  = $entry.Value
        $value = [ordered]@{
            connectionId   = "[resourceId('Microsoft.Web/connections', variables('$($conn.VariableName)'))]"
            connectionName = "[variables('$($conn.VariableName)')]"
            id             = Get-ManagedApiIdExpression -ApiName $conn.ApiName
        }
        if ($conn.UsesManagedIdentity) {
            $value['connectionProperties'] = [ordered]@{
                authentication = [ordered]@{ type = 'ManagedServiceIdentity' }
            }
        }
        $values[$entry.Key] = $value
    }
    return $values
}

# ---------------------------------------------------------------------------
# Portability: hardcoded IDs to ARM expressions
# ---------------------------------------------------------------------------
function Get-PortableContext {
    <#
    .SYNOPSIS
        Builds the replacement rules used to turn hardcoded environment
        values in a workflow definition into ARM expressions.
    .DESCRIPTION
        GUIDs (subscription ID, workspace ID) are replaced wherever they
        appear. Resource-group and workspace names are short and could
        collide with ordinary text, so they are only replaced in ARM path
        position (after resourceGroups/ or workspaces/, optionally wrapped
        in the @{encodeURIComponent('...')} form connector paths use), or
        as the whole value of a property that names one (the Azure Monitor
        Logs connector's resourcegroups and resourcename query fields).

        Rules are listed in priority order. Where two rules match the same
        text, the earlier rule wins, so a workflow reference resolves to
        AutomationResourceGroup even when the playbooks share the
        workspace's resource group.

        UsedParameters is filled in as rules fire, so the template only
        declares the parameters its expressions reference.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$SubscriptionId,
        [Parameter(Mandatory)] [string]$PlaybookResourceGroup,
        [Parameter(Mandatory)] [string]$WorkspaceResourceGroup,
        [Parameter(Mandatory)] [string]$WorkspaceName,
        [string]$WorkspaceId
    )

    $wrap = "(?:@\{encodeURIComponent\(')?"
    $end  = "(?=['/?&)\s]|$)"
    $sub  = [regex]::Escape($SubscriptionId)
    $prg  = [regex]::Escape($PlaybookResourceGroup)
    $wrg  = [regex]::Escape($WorkspaceResourceGroup)
    $ws   = [regex]::Escape($WorkspaceName)

    $rules = [System.Collections.Generic.List[hashtable]]::new()
    $rules.Add(@{ Pattern = "(?i)(?<v>$sub)"; Expression = 'subscription().subscriptionId'; Parameter = $null })
    if ($WorkspaceId) {
        $rules.Add(@{ Pattern = "(?i)(?<v>$([regex]::Escape($WorkspaceId)))"; Expression = "parameters('WorkspaceId')"; Parameter = 'WorkspaceId' })
    }
    $rules.Add(@{ Pattern = "(?i)resourceGroups/$wrap(?<v>$prg)(?=(?:'\)\})?/providers/Microsoft\.Logic/workflows/)"; Expression = "parameters('AutomationResourceGroup')"; Parameter = 'AutomationResourceGroup' })
    $rules.Add(@{ Pattern = "(?i)resourceGroups/$wrap(?<v>$wrg)$end"; Expression = "parameters('SentinelResourceGroupName')"; Parameter = 'SentinelResourceGroupName' })
    $rules.Add(@{ Pattern = "(?i)resourceGroups/$wrap(?<v>$prg)$end"; Expression = "parameters('AutomationResourceGroup')"; Parameter = 'AutomationResourceGroup' })
    $rules.Add(@{ Pattern = "(?i)workspaces/$wrap(?<v>$ws)$end"; Expression = "parameters('SentinelWorkpaceName')"; Parameter = 'SentinelWorkpaceName' })

    return @{
        Rules                  = $rules.ToArray()
        PlaybookResourceGroup  = $PlaybookResourceGroup
        WorkspaceResourceGroup = $WorkspaceResourceGroup
        WorkspaceName          = $WorkspaceName
        UsedParameters         = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    }
}

function ConvertTo-ArmStringValue {
    <#
    .SYNOPSIS
        Rewrites one string so ARM evaluates it back to the same value for
        the target environment.
    .DESCRIPTION
        With no rule matches the string is returned unchanged, except that
        a literal which starts with [ and ends with ] gets the [[ escape
        ARM needs so it is not evaluated as an expression. With matches,
        the string becomes a concat() of literal segments (single quotes
        doubled) and the matched expressions, or a bare expression when the
        whole string was one matched value.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$Value,
        [Parameter(Mandatory)] [hashtable]$Context
    )

    $hits = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $Context.Rules.Count; $i++) {
        foreach ($m in [regex]::Matches($Value, $Context.Rules[$i].Pattern)) {
            $group = $m.Groups['v']
            $hits.Add([pscustomobject]@{ Start = $group.Index; Length = $group.Length; Priority = $i })
        }
    }

    if ($hits.Count -eq 0) {
        if ($Value.StartsWith('[') -and $Value.EndsWith(']')) { return "[$Value" }
        return $Value
    }

    $parts  = [System.Collections.Generic.List[string]]::new()
    $cursor = 0
    foreach ($hit in ($hits | Sort-Object Start, Priority)) {
        if ($hit.Start -lt $cursor) { continue }
        if ($hit.Start -gt $cursor) {
            $parts.Add("'" + $Value.Substring($cursor, $hit.Start - $cursor).Replace("'", "''") + "'")
        }
        $rule = $Context.Rules[$hit.Priority]
        $parts.Add($rule.Expression)
        if ($rule.Parameter) { [void]$Context.UsedParameters.Add($rule.Parameter) }
        $cursor = $hit.Start + $hit.Length
    }
    if ($cursor -lt $Value.Length) {
        $parts.Add("'" + $Value.Substring($cursor).Replace("'", "''") + "'")
    }

    if ($parts.Count -eq 1) { return "[$($parts[0])]" }
    return "[concat($($parts -join ', '))]"
}

function ConvertTo-PortableValue {
    <#
    .SYNOPSIS
        Walks a workflow definition and returns a copy with every string
        passed through ConvertTo-ArmStringValue.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()] $Value,
        [Parameter(Mandatory)] [hashtable]$Context,
        [string]$PropertyName
    )

    if ($null -eq $Value) { return $null }

    if ($Value -is [string]) {
        if ($PropertyName -match '^(resourcegroups?|resourceGroupName)$') {
            if ($Value -ieq $Context.WorkspaceResourceGroup) {
                [void]$Context.UsedParameters.Add('SentinelResourceGroupName')
                return "[parameters('SentinelResourceGroupName')]"
            }
            if ($Value -ieq $Context.PlaybookResourceGroup) {
                [void]$Context.UsedParameters.Add('AutomationResourceGroup')
                return "[parameters('AutomationResourceGroup')]"
            }
        }
        if ($PropertyName -match '^(resourcename|workspaceName|workspace)$' -and $Value -ieq $Context.WorkspaceName) {
            [void]$Context.UsedParameters.Add('SentinelWorkpaceName')
            return "[parameters('SentinelWorkpaceName')]"
        }
        return ConvertTo-ArmStringValue -Value $Value -Context $Context
    }

    if ($Value -is [System.Collections.IDictionary]) {
        $out = [ordered]@{}
        foreach ($key in $Value.Keys) {
            $out[$key] = ConvertTo-PortableValue -Value $Value[$key] -Context $Context -PropertyName $key
        }
        return $out
    }

    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $out = [ordered]@{}
        foreach ($p in $Value.PSObject.Properties) {
            $out[$p.Name] = ConvertTo-PortableValue -Value $p.Value -Context $Context -PropertyName $p.Name
        }
        return $out
    }

    if ($Value -is [System.Collections.IEnumerable]) {
        $items = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $Value) {
            $items.Add((ConvertTo-PortableValue -Value $item -Context $Context -PropertyName $PropertyName))
        }
        return , $items.ToArray()
    }

    return $Value
}

# ---------------------------------------------------------------------------
# Secret scan
# ---------------------------------------------------------------------------
function Find-PlaintextSecret {
    <#
    .SYNOPSIS
        Returns the definition paths of values that look like secrets held
        in plain text.
    .DESCRIPTION
        Flags literal (non-expression) values in three places: credential
        headers (Authorization, x-api-key and similar), the secret fields
        of an HTTP authentication block (password, secret, pfx, value), and
        key-bearing query parameters in a uri (code, sig, key, apikey).
        Values that start with @ or contain @{ are workflow expressions,
        typically Key Vault or parameter lookups, and are not flagged.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)] $Definition
    )

    $findings = [System.Collections.Generic.List[string]]::new()
    Find-PlaintextSecretInNode -Node $Definition -Path '' -Findings $findings
    return $findings.ToArray()
}

function Find-PlaintextSecretInNode {
    param(
        [AllowNull()] $Node,
        [string]$Path,
        [System.Collections.Generic.List[string]]$Findings
    )

    if ($null -eq $Node -or $Node -is [string]) { return }

    $isObject = $Node -is [System.Management.Automation.PSCustomObject] -or $Node -is [System.Collections.IDictionary]
    if (-not $isObject) {
        if ($Node -is [System.Collections.IEnumerable]) {
            $i = 0
            foreach ($item in $Node) {
                Find-PlaintextSecretInNode -Node $item -Path "$Path[$i]" -Findings $Findings
                $i++
            }
        }
        return
    }

    $parent = ($Path -split '\.')[-1]
    foreach ($name in @(Get-PropertyNames $Node)) {
        $value     = Get-SafeProperty $Node $name
        $childPath = if ($Path) { "$Path.$name" } else { $name }

        if ($value -is [string]) {
            $isLiteral = $value -and -not $value.StartsWith('@') -and $value -notmatch '@\{'
            $flag = $false
            if ($parent -eq 'headers' -and $name -match '^(authorization|x-api-key|api-key|apikey|x-apikey|ocp-apim-subscription-key|x-functions-key)$') {
                $flag = $isLiteral
            }
            elseif ($parent -eq 'authentication' -and $name -match '^(password|secret|pfx|value)$') {
                $flag = $isLiteral
            }
            elseif ($name -eq 'uri' -and $value -match '[?&](code|sig|key|apikey|api_key|api-key)=(?!@)[^&]+') {
                $flag = $true
            }
            if ($flag) { $Findings.Add($childPath) }
            continue
        }

        Find-PlaintextSecretInNode -Node $value -Path $childPath -Findings $Findings
    }
}

# ---------------------------------------------------------------------------
# Template assembly
# ---------------------------------------------------------------------------
function Build-ArmTemplate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $LogicApp,
        [Parameter(Mandatory)] [string]$Category,
        [Parameter(Mandatory)] [string]$PlaybookName,
        [Parameter(Mandatory)] [string]$AuthorName,
        [Parameter(Mandatory)] [hashtable]$Context
    )

    $properties = Get-SafeProperty $LogicApp 'properties'
    $definition = Get-SafeProperty $properties 'definition'
    $connValues = Get-SafeProperty (Get-SafeProperty (Get-SafeProperty $properties 'parameters') '$connections') 'value'

    $connectionMap      = Get-ConnectionMap -ConnectionsValue $connValues
    $portableDefinition = ConvertTo-PortableValue -Value $definition -Context $Context

    # ----- Parameters -----
    # Sentinel-triggered categories always declare the resource group and
    # workspace parameters (matching the existing templates); anything else
    # an expression references is declared on top.
    $parameters = [ordered]@{
        PlaybookName = [ordered]@{ defaultValue = $PlaybookName; type = 'string' }
    }
    $sentinelCategory = $Category -in @('Incident', 'Entity', 'Alert', 'Watchlist')
    foreach ($name in @('AutomationResourceGroup', 'SentinelWorkpaceName', 'SentinelResourceGroupName', 'WorkspaceId')) {
        $baseline = $sentinelCategory -and $name -in @('AutomationResourceGroup', 'SentinelWorkpaceName')
        if ($baseline -or $Context.UsedParameters.Contains($name)) {
            $parameters[$name] = [ordered]@{ defaultValue = ''; type = 'string' }
        }
    }

    # ----- Workflow resource -----
    $state = Get-SafeProperty $properties 'state'
    $workflowProperties = [ordered]@{
        provisioningState = 'Succeeded'
        state             = $(if ($state) { $state } else { 'Enabled' })
        definition        = $portableDefinition
    }

    if ($connectionMap.Count -gt 0) {
        $workflowProperties['parameters'] = [ordered]@{
            '$connections' = [ordered]@{
                value = Build-ConnectionParameters -ConnectionMap $connectionMap
            }
        }
    }

    if ($Category -eq 'Module') {
        $workflowProperties['accessControl'] = [ordered]@{
            triggers = [ordered]@{ allowedCallerIpAddresses = @() }
            actions  = [ordered]@{ allowedCallerIpAddresses = @() }
        }
    }

    $dependsOn = @($connectionMap.Values | ForEach-Object {
        "[resourceId('Microsoft.Web/connections', variables('$($_.VariableName)'))]"
    })

    $resources = [System.Collections.Generic.List[object]]::new()
    $resources.Add([ordered]@{
        properties = $workflowProperties
        name       = "[parameters('PlaybookName')]"
        type       = 'Microsoft.Logic/workflows'
        location   = '[resourceGroup().location]'
        tags       = [ordered]@{ Source = 'Sentinel-As-Code' }
        identity   = [ordered]@{ type = 'SystemAssigned' }
        apiVersion = $script:WorkflowApiVersion
        dependsOn  = $dependsOn
    })
    foreach ($connectionResource in @(Build-ConnectionResources -ConnectionMap $connectionMap)) {
        $resources.Add($connectionResource)
    }

    # ----- Metadata -----
    $entities    = @(Get-WorkflowEntities -Definition $definition)
    $description = Get-WorkflowDescription -LogicApp $LogicApp -Category $Category -PlaybookName $PlaybookName -Entities $entities

    return [ordered]@{
        '$schema'      = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#'
        contentVersion = '1.0.0.0'
        metadata       = [ordered]@{
            title          = $PlaybookName
            description    = $description
            lastUpdateTime = (Get-Date -Format 'dd-MM-yyyy')
            entities       = $entities
            tags           = @($Category, 'Source: Sentinel-As-Code')
            support        = [ordered]@{ tier = 'community' }
            author         = [ordered]@{ name = $AuthorName }
        }
        parameters     = $parameters
        variables      = Build-ConnectionVariables -ConnectionMap $connectionMap
        resources      = $resources.ToArray()
    }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
function Invoke-PlaybookExport {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([int])]
    param(
        [string]$SubscriptionId,
        [Parameter(Mandatory)] [string]$ResourceGroup,
        [Parameter(Mandatory)] [string]$Workspace,
        [Parameter(Mandatory)] [string]$Region,
        [string]$PlaybookResourceGroup,
        [Parameter(Mandatory)] [string]$OutputPath,
        [string]$NameFilter,
        [Parameter(Mandatory)] [string]$Author,
        [switch]$Force,
        [switch]$IsGov
    )

    $repoRoot   = Split-Path $PSScriptRoot -Parent
    $playbookRg = if ($PlaybookResourceGroup) { $PlaybookResourceGroup } else { $ResourceGroup }

    Write-PipelineMessage 'Sentinel Playbook Export' -Level Section
    Write-PipelineMessage "  Resource Group:          $ResourceGroup" -Level Info
    Write-PipelineMessage "  Workspace:               $Workspace" -Level Info
    Write-PipelineMessage "  Playbook resource group: $playbookRg" -Level Info
    Write-PipelineMessage "  Output path:             $OutputPath" -Level Info
    if ($NameFilter) { Write-PipelineMessage "  Name filter:             $NameFilter" -Level Info }

    $ctx = Connect-AzureEnvironment `
        -ResourceGroup         $ResourceGroup `
        -Workspace             $Workspace `
        -Region                $Region `
        -SubscriptionId        $SubscriptionId `
        -IsGov:$IsGov `
        -PlaybookResourceGroup $playbookRg

    if (-not $ctx.WorkspaceId) {
        Write-PipelineMessage 'Workspace ID unavailable; hardcoded workspace IDs will stay in the exported definitions.' -Level Warning
    }

    Write-PipelineMessage 'Listing Logic Apps' -Level Section
    $listUri = "$($ctx.ServerUrl)/subscriptions/$($ctx.SubscriptionId)/resourceGroups/$playbookRg/providers/Microsoft.Logic/workflows?api-version=$($script:LogicAppApiVersion)&`$top=100"
    $logicApps = [System.Collections.Generic.List[object]]::new()
    $page = Invoke-SentinelApi -Uri $listUri -Method Get -Headers $ctx.AuthHeader
    while ($true) {
        foreach ($item in @(Get-SafeProperty $page 'value')) {
            if ($null -ne $item) { $logicApps.Add($item) }
        }
        $nextLink = Get-SafeProperty $page 'nextLink'
        if (-not $nextLink) { break }
        $page = Invoke-SentinelApi -Uri $nextLink -Method Get -Headers $ctx.AuthHeader
    }

    $apps = @($logicApps)
    if ($NameFilter) {
        $apps = @($apps | Where-Object { $_.name -like $NameFilter })
    }
    Write-PipelineMessage "Found $($logicApps.Count) Logic App(s); $($apps.Count) selected for export." -Level Info

    $counters = [ordered]@{ Exported = 0; Skipped = 0; Failed = 0; SecretWarnings = 0 }

    foreach ($app in $apps) {
        $appName = [string]$app.name
        try {
            $definition = Get-SafeProperty (Get-SafeProperty $app 'properties') 'definition'
            if (-not $definition) {
                $app = Invoke-SentinelApi -Uri "$($ctx.ServerUrl)$($app.id)?api-version=$($script:LogicAppApiVersion)" -Method Get -Headers $ctx.AuthHeader
                $definition = Get-SafeProperty (Get-SafeProperty $app 'properties') 'definition'
            }
            if (-not $definition) {
                Write-PipelineMessage "Skipping '$appName': no workflow definition returned." -Level Warning
                $counters.Skipped++
                continue
            }

            $category   = Get-TriggerCategory -Definition $definition
            $fileName   = Get-PlaybookFileName -LogicAppName $appName
            $outputFile = Join-Path (Join-Path $OutputPath $category) "$fileName.json"
            $shownPath  = [System.IO.Path]::GetRelativePath($repoRoot, $outputFile)

            if ((Test-Path $outputFile) -and -not $Force) {
                Write-PipelineMessage "Skipping '$appName': $shownPath exists (use -Force to overwrite)." -Level Info
                $counters.Skipped++
                continue
            }

            $portable = Get-PortableContext `
                -SubscriptionId         $ctx.SubscriptionId `
                -PlaybookResourceGroup  $playbookRg `
                -WorkspaceResourceGroup $ResourceGroup `
                -WorkspaceName          $Workspace `
                -WorkspaceId            $ctx.WorkspaceId

            $template = Build-ArmTemplate `
                -LogicApp     $app `
                -Category     $category `
                -PlaybookName $appName `
                -AuthorName   $Author `
                -Context      $portable

            foreach ($finding in @(Find-PlaintextSecret -Definition $definition)) {
                Write-PipelineMessage "  '$appName' holds a plain-text secret at $finding. Move it to Key Vault before committing." -Level Warning
                $counters.SecretWarnings++
            }

            $json = $template | ConvertTo-Json -Depth 100
            if ($PSCmdlet.ShouldProcess($shownPath, 'Write playbook template')) {
                $categoryDir = Split-Path $outputFile -Parent
                if (-not (Test-Path $categoryDir)) {
                    New-Item -Path $categoryDir -ItemType Directory -Force | Out-Null
                }
                Set-Content -Path $outputFile -Value $json -Encoding utf8NoBOM
                Write-PipelineMessage "Exported '$appName' ($category) -> $shownPath" -Level Success
            }
            $counters.Exported++
        }
        catch {
            Write-PipelineMessage "Failed to export '$appName': $($_.Exception.Message)" -Level Error
            $counters.Failed++
        }
    }

    Write-PipelineMessage 'Export summary' -Level Section
    Write-PipelineMessage "  Exported: $($counters.Exported)" -Level Info
    Write-PipelineMessage "  Skipped:  $($counters.Skipped)" -Level Info
    Write-PipelineMessage "  Failed:   $($counters.Failed)" -Level Info
    if ($counters.SecretWarnings -gt 0) {
        Write-PipelineMessage "  Plain-text secret warnings: $($counters.SecretWarnings)" -Level Warning
    }

    return $counters.Failed
}

$exportParams = @{
    SubscriptionId        = $SubscriptionId
    ResourceGroup         = $ResourceGroup
    Workspace             = $Workspace
    Region                = $Region
    PlaybookResourceGroup = $PlaybookResourceGroup
    OutputPath            = $OutputPath
    NameFilter            = $NameFilter
    Author                = $Author
    Force                 = $Force
    IsGov                 = $IsGov
}
$failedCount = Invoke-PlaybookExport @exportParams
if ($failedCount -gt 0) { exit 1 }

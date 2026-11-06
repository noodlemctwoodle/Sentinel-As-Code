#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester 5 tests for Export-iSOCContent and the workbook and playbook
    export handlers.

.DESCRIPTION
    Covers:
      - The workbook helpers, with the cases of
        Tests/Test-ExportSentinelWorkbooks.Tests.ps1 carried over: folder
        names, the workspace suffix, the workspace resource id placeholder,
        the metadata merge (and its key order, MIGRATION.md edit E26).
      - The playbook helpers, with the cases of the unmerged playbook
        exporter's suite (847ef86:Tests/Test-ExportPlaybooks.Tests.ps1)
        carried over: trigger categories, file names, entities, ARM
        expressions proved by evaluating them back, connections, the
        template's invariants and the plain-text secret scan.
      - The handlers: the workspace reads, the classifiers (by GUID, by
        PlaybookName, ambiguous, Content Hub, unreadable, empty), the files
        written, and a playbook left alone when only its date would change
        (MIGRATION.md edit E27); a playbook written as Bicep by default
        (E48), compiled through the Bicep CLI and deploying what the JSON
        export deploys, with its secrets warned about and its date kept.
      - Export-iSOCContent: outcomes, -Force, -Name, -Path, -WhatIf,
        -Format Json, a JSON playbook the repository has kept as JSON, paths
        held by another item or claimed earlier in the run, the exit code.
      - Whole runs against a stand-in workspace built from this
        repository's workbooks (_helpers/ExportStandIn.psm1): every case
        counted, curated metadata kept, every page of a list read, and the
        behaviour MIGRATION.md edits E25 to E27 describe.

    Parity with Tools/Export-SentinelWorkbooks.ps1 and the unmerged
    playbook exporter (847ef86:Tools/Export-Playbooks.ps1), run against the
    same stand-in with the same files and counts, was proven on
    release/26.11.0 before they were removed.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCDeployments/Export.Tests.ps1

    Runs the whole suite.

.NOTES
    File:         Tests/iSOCDeployments/Export.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.3.0
    Last Updated: 2026-11-06
    Requires:     PowerShell 7.2+, Pester 5+, the Bicep CLI
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:repoRoot 'Modules/iSOCDeployments/iSOCDeployments.psd1') -Force
    Import-Module (Join-Path $PSScriptRoot '_helpers/Parity.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot '_helpers/ExportStandIn.psm1') -Force

    $script:Sub = '11111111-2222-3333-4444-555555555555'
    $script:WsId = '99999999-8888-7777-6666-555555555555'
    $script:wsPath = "/subscriptions/$($script:Sub)/resourceGroups/rg-sentinel/providers/Microsoft.OperationalInsights/workspaces/law-lab"
    $script:wbBase = "/subscriptions/$($script:Sub)/resourceGroups/rg-sentinel/providers/Microsoft.Insights/workbooks"
    $script:laBase = "/subscriptions/$($script:Sub)/resourceGroups/rg-automation/providers/Microsoft.Logic/workflows"
    $script:context = InModuleScope iSOCDeployments -Parameters @{ S = $script:Sub; W = $script:wsPath; I = $script:WsId } {
        param($S, $W, $I)
        New-iSOCContext -Value @{
            TenantId = 't'; SubscriptionId = $S; ResourceGroup = 'rg-sentinel'; WorkspaceName = 'law-lab'
            WorkspaceResourceId = $W; WorkspaceId = $I; Region = 'uksouth'; PlaybookResourceGroup = 'rg-automation'; Environment = 'AzureCloud'
            IsGov = $false; ArmUrl = 'https://management.azure.com'; GraphUrl = 'https://graph.microsoft.com'; Account = 'a'
        }
    }

    function Invoke-Private {
        param([string] $Command, [hashtable] $Arguments = @{})
        InModuleScope iSOCDeployments -Parameters @{ C = $Command; A = $Arguments } { param($C, $A) & $C @A }
    }
    function Get-Type { param([string] $Name) Invoke-Private Get-iSOCContentTypeDefinition @{ Name = $Name } }

    # The value ARM substitutes for each expression the exporter writes.
    $script:ExpressionValues = @{
        'subscription().subscriptionId'           = $script:Sub
        "parameters('WorkspaceId')"               = $script:WsId
        "parameters('AutomationResourceGroup')"   = 'rg-automation'
        "parameters('SentinelResourceGroupName')" = 'rg-sentinel'
        "parameters('SentinelWorkpaceName')"      = 'law-lab'
    }

    function New-TestContext {
        param([string] $PlaybookResourceGroup = 'rg-automation')
        Invoke-Private Get-iSOCPortableContext @{ SubscriptionId = $script:Sub; PlaybookResourceGroup = $PlaybookResourceGroup; WorkspaceResourceGroup = 'rg-sentinel'; WorkspaceName = 'law-lab'; WorkspaceId = $script:WsId }
    }

    # A small ARM string evaluator: [[ escapes, bare expressions, and
    # concat() of single-quoted literals and the known expressions.
    function Resolve-ArmString {
        param([string] $Value)
        if ($Value.StartsWith('[[')) { return $Value.Substring(1) }
        if (-not ($Value.StartsWith('[') -and $Value.EndsWith(']'))) { return $Value }
        $inner = $Value.Substring(1, $Value.Length - 2)
        if ($script:ExpressionValues.ContainsKey($inner)) { return $script:ExpressionValues[$inner] }
        if (-not ($inner.StartsWith('concat(') -and $inner.EndsWith(')'))) { throw "Unsupported expression: $Value" }
        $argText = $inner.Substring(7, $inner.Length - 8)
        $result = [System.Text.StringBuilder]::new()
        $i = 0
        while ($i -lt $argText.Length) {
            while ($i -lt $argText.Length -and $argText[$i] -in @(',', ' ')) { $i++ }
            if ($i -ge $argText.Length) { break }
            if ($argText[$i] -eq "'") {
                $i++
                while ($true) {
                    if ($argText[$i] -eq "'") {
                        if ($i + 1 -lt $argText.Length -and $argText[$i + 1] -eq "'") { [void]$result.Append("'"); $i += 2; continue }
                        $i++
                        break
                    }
                    [void]$result.Append($argText[$i])
                    $i++
                }
            }
            else {
                $start = $i
                $depth = 0
                $inQuote = $false
                while ($i -lt $argText.Length) {
                    $ch = $argText[$i]
                    if ($ch -eq "'") { $inQuote = -not $inQuote }
                    elseif (-not $inQuote -and $ch -eq '(') { $depth++ }
                    elseif (-not $inQuote -and $ch -eq ')') { $depth-- }
                    elseif (-not $inQuote -and $depth -eq 0 -and $ch -eq ',') { break }
                    $i++
                }
                $expr = $argText.Substring($start, $i - $start).Trim()
                if (-not $script:ExpressionValues.ContainsKey($expr)) { throw "Unknown expression: $expr" }
                [void]$result.Append($script:ExpressionValues[$expr])
            }
        }
        $result.ToString()
    }

    # The path of every string in the converted copy that does not
    # evaluate back to the original.
    function Compare-PortableRoundTrip {
        param($Original, $Converted, [string] $Path = '')
        $mismatches = [System.Collections.Generic.List[string]]::new()
        if ($Original -is [string]) {
            if ((Resolve-ArmString -Value $Converted) -cne $Original) { $mismatches.Add($Path) }
        }
        elseif ($Original -is [System.Management.Automation.PSCustomObject]) {
            foreach ($p in $Original.PSObject.Properties) {
                foreach ($m in (Compare-PortableRoundTrip -Original $p.Value -Converted $Converted[$p.Name] -Path "$Path.$($p.Name)")) { $mismatches.Add($m) }
            }
        }
        elseif ($Original -is [System.Collections.IEnumerable]) {
            $orig = @($Original)
            $conv = @($Converted)
            for ($i = 0; $i -lt $orig.Count; $i++) {
                foreach ($m in (Compare-PortableRoundTrip -Original $orig[$i] -Converted $conv[$i] -Path "$Path[$i]")) { $mismatches.Add($m) }
            }
        }
        , $mismatches.ToArray()
    }

    # A live-shaped Logic App: an incident trigger, a module call, workspace
    # references in three styles, a managed-identity Sentinel connection,
    # an OAuth Office 365 connection and a plain-text API key.
    $script:FixtureJson = @'
{
  "id": "/subscriptions/{SUB}/resourceGroups/rg-automation/providers/Microsoft.Logic/workflows/Incident-StandInIsolate",
  "name": "Incident-StandInIsolate",
  "properties": {
    "state": "Disabled",
    "definition": {
      "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
      "contentVersion": "1.0.0.0",
      "parameters": { "$connections": { "defaultValue": {}, "type": "Object" } },
      "triggers": {
        "Microsoft_Sentinel_incident": {
          "type": "ApiConnectionWebhook",
          "inputs": {
            "body": { "callback_url": "@{listCallbackUrl()}" },
            "host": { "connection": { "name": "@parameters('$connections')['azuresentinel']['connectionId']" } },
            "path": "/incident-creation"
          }
        }
      },
      "actions": {
        "Entities_-_Get_Hosts": { "type": "ApiConnection", "inputs": { "method": "post", "path": "/entities/host" } },
        "Call_module": {
          "type": "Workflow",
          "inputs": {
            "host": {
              "workflow": { "id": "/subscriptions/{SUB}/resourceGroups/rg-automation/providers/Microsoft.Logic/workflows/Module-AddComment" },
              "triggerName": "manual"
            }
          }
        },
        "Update_incident": {
          "type": "ApiConnection",
          "inputs": {
            "method": "put",
            "path": "/Incidents/subscriptions/@{encodeURIComponent('{SUB}')}/resourceGroups/@{encodeURIComponent('rg-sentinel')}/workspaces/@{encodeURIComponent('{WSID}')}/incidents/@{triggerBody()?['object']?['name']}"
          }
        },
        "List_incidents": {
          "type": "Http",
          "inputs": {
            "method": "GET",
            "uri": "https://management.azure.com/subscriptions/{SUB}/resourceGroups/rg-sentinel/providers/Microsoft.OperationalInsights/workspaces/law-lab/providers/Microsoft.SecurityInsights/incidents?api-version=2024-03-01",
            "authentication": { "type": "ManagedServiceIdentity" }
          }
        },
        "Run_query": {
          "type": "ApiConnection",
          "inputs": {
            "path": "/queryData",
            "queries": { "subscriptions": "{SUB}", "resourcegroups": "rg-sentinel", "resourcetype": "Log Analytics Workspace", "resourcename": "law-lab" }
          }
        },
        "Lookup_reputation": {
          "type": "Http",
          "inputs": { "method": "GET", "uri": "https://api.example.com/ip", "headers": { "x-apikey": "literal-key-value" } }
        },
        "Send_email": {
          "type": "ApiConnection",
          "inputs": { "host": { "connection": { "name": "@parameters('$connections')['office365']['connectionId']" } }, "path": "/v2/Mail" }
        },
        "Add_comment": {
          "type": "ApiConnection",
          "inputs": { "body": { "message": "Escalated by the rg-sentinel team, Tom's queue" }, "path": "/Incidents/Comment" }
        },
        "Compose_array": { "type": "Compose", "inputs": "[1,2,3]" },
        "Compose_list": { "type": "Compose", "inputs": ["only-item"] }
      }
    },
    "parameters": {
      "$connections": {
        "value": {
          "azuresentinel": {
            "connectionId": "/subscriptions/{SUB}/resourceGroups/rg-automation/providers/Microsoft.Web/connections/azuresentinel-Incident-StandInIsolate",
            "connectionName": "azuresentinel-Incident-StandInIsolate",
            "connectionProperties": { "authentication": { "type": "ManagedServiceIdentity" } },
            "id": "/subscriptions/{SUB}/providers/Microsoft.Web/locations/uksouth/managedApis/azuresentinel"
          },
          "office365": {
            "connectionId": "/subscriptions/{SUB}/resourceGroups/rg-automation/providers/Microsoft.Web/connections/office365",
            "connectionName": "office365",
            "id": "/subscriptions/{SUB}/providers/Microsoft.Web/locations/uksouth/managedApis/office365"
          }
        }
      }
    }
  }
}
'@.Replace('{SUB}', $script:Sub).Replace('{WSID}', $script:WsId)

    function Get-FixtureLogicApp { $script:FixtureJson | ConvertFrom-Json -Depth 100 }
    function ConvertTo-TemplateHashtable { param($Template) $Template | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -AsHashtable }

    # A Logic App as the API returns it.
    function New-LogicApp {
        param([string] $Name, [hashtable] $Triggers, [hashtable] $Actions = @{}, [hashtable] $Connections = @{}, [string] $State = 'Enabled', [switch] $NoDefinition)
        $app = [ordered]@{ id = "$($script:laBase)/$Name"; name = $Name; type = 'Microsoft.Logic/workflows'; location = 'uksouth'; properties = [ordered]@{ state = $State } }
        if (-not $NoDefinition) {
            $app.properties.definition = [ordered]@{
                '$schema'      = 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
                contentVersion = '1.0.0.0'
                triggers       = $Triggers
                actions        = $Actions
            }
            if ($Connections.Count -gt 0) { $app.properties.parameters = @{ '$connections' = @{ value = $Connections } } }
        }
        $app | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
    }
    function New-Connection {
        param([string] $Api, [switch] $ManagedIdentity)
        $value = [ordered]@{ connectionId = "/subscriptions/$($script:Sub)/resourceGroups/rg-automation/providers/Microsoft.Web/connections/$Api"; id = "/subscriptions/$($script:Sub)/providers/Microsoft.Web/locations/uksouth/managedApis/$Api" }
        if ($ManagedIdentity) { $value.connectionProperties = @{ authentication = @{ type = 'ManagedServiceIdentity' } } }
        $value
    }

    # A workbook as the API returns it.
    function New-Workbook {
        param([string] $Name, [string] $DisplayName, [AllowNull()] [string] $SerializedData, [string] $Category = 'sentinel', [string] $Description = '', [switch] $NoContent)
        $properties = [ordered]@{ displayName = $DisplayName; description = $Description; category = $Category; sourceId = $script:wsPath.ToLowerInvariant(); version = '1.0' }
        if (-not $NoContent) { $properties.serializedData = $SerializedData }
        [ordered]@{ id = "$($script:wbBase)/$Name"; name = $Name; type = 'microsoft.insights/workbooks'; kind = 'shared'; location = 'uksouth'; properties = $properties } |
            ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
    }
    function New-GalleryTemplate {
        param([string] $Title, [switch] $Workspace)
        $template = [ordered]@{ version = 'Notebook/1.0'; items = @([ordered]@{ type = 1; content = [ordered]@{ json = "## $Title" }; name = 'text - 0' }); isLocked = $false }
        $template.fallbackResourceIds = @($(if ($Workspace) { $script:wsPath.ToLowerInvariant() } else { 'Azure Monitor' }))
        ConvertTo-Json -InputObject $template -Depth 20 -Compress
    }

    function New-RepoCopy {
        param([string[]] $Folder = @('Content/Workbooks', 'Content/Playbooks'))
        $copy = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $copy 'Content') -Force | Out-Null
        foreach ($f in $Folder) { Copy-Item -LiteralPath (Join-Path $script:repoRoot $f) -Destination (Join-Path $copy 'Content') -Recurse }
        $copy
    }

    function Get-TreeFile {
        param([string] $Root, [string] $Folder)
        $base = Join-Path $Root $Folder
        if (-not (Test-Path -LiteralPath $base)) { return @() }
        $files = @(Get-ChildItem -LiteralPath $base -Recurse -File | ForEach-Object { [System.IO.Path]::GetRelativePath($Root, $_.FullName).Replace('\', '/') })
        [Array]::Sort($files, [System.StringComparer]::Ordinal)
        $files
    }
}

AfterAll {
    Remove-Module iSOCDeployments -ErrorAction SilentlyContinue
}

Describe 'Workbook helpers (carried over from Test-ExportSentinelWorkbooks.Tests.ps1)' {
    It 'makes <DisplayName> the folder <Expected>' -ForEach @(
        @{ DisplayName = 'Microsoft Sentinel Monitoring'; Expected = 'MicrosoftSentinelMonitoring' }
        @{ DisplayName = 'Sentinel Monitoring'; Expected = 'SentinelMonitoring' }
        @{ DisplayName = 'Microsoft Sentinel Cost (GBP) v2'; Expected = 'MicrosoftSentinelCostGbpV2' }
        @{ DisplayName = 'pfSense Firewall'; Expected = 'PfSenseFirewall' }
        @{ DisplayName = 'Perimeter 81 v2'; Expected = 'Perimeter81V2' }
        @{ DisplayName = 'machines and networks'; Expected = 'MachinesAndNetworks' }
        @{ DisplayName = 'MicrosoftSentinelMonitoring'; Expected = 'MicrosoftSentinelMonitoring' }
        @{ DisplayName = 'Bad/Name:With*Illegal?Chars'; Expected = 'BadNameWithIllegalChars' }
        @{ DisplayName = 'Data   Collection    Rules'; Expected = 'DataCollectionRules' }
        @{ DisplayName = 'Summary Rules Workbook'; Expected = 'SummaryRulesWorkbook' }
        @{ DisplayName = 'Microsoft Sentinel Optimization Workbook'; Expected = 'MicrosoftSentinelOptimizationWorkbook' }
        @{ DisplayName = 'Data Collection Rule Toolkit'; Expected = 'DataCollectionRuleToolkit' }
        @{ DisplayName = 'Sentinel Data Lake'; Expected = 'SentinelDataLake' }
    ) {
        Invoke-Private ConvertTo-iSOCWorkbookFolderName @{ DisplayName = $DisplayName } | Should -BeExactly $Expected
    }

    It 'strips <Case>' -ForEach @(
        @{ Case = 'a trailing " - <workspace>"'; DisplayName = 'Data Collection Rule Toolkit - stl-eus-siem-law'; Expected = 'Data Collection Rule Toolkit' }
        @{ Case = 'nothing when there is no suffix'; DisplayName = 'Microsoft Sentinel Cost (GBP) v2'; Expected = 'Microsoft Sentinel Cost (GBP) v2' }
        @{ Case = 'nothing mid-string'; DisplayName = 'stl-eus-siem-law - Overview'; Expected = 'stl-eus-siem-law - Overview' }
        @{ Case = 'nothing flush against the name'; DisplayName = 'Toolkit-stl-eus-siem-law'; Expected = 'Toolkit-stl-eus-siem-law' }
        @{ Case = 'nothing in another case'; DisplayName = 'Toolkit - STL-EUS-SIEM-LAW'; Expected = 'Toolkit - STL-EUS-SIEM-LAW' }
    ) {
        Invoke-Private Get-iSOCWorkbookDisplayName @{ DisplayName = $DisplayName; WorkspaceName = 'stl-eus-siem-law' } | Should -BeExactly $Expected
    }

    It 'escapes regex characters in the workspace name' {
        Invoke-Private Get-iSOCWorkbookDisplayName @{ DisplayName = 'Toolkit - law.(lab)+'; WorkspaceName = 'law.(lab)+' } | Should -BeExactly 'Toolkit'
        Invoke-Private Get-iSOCWorkbookDisplayName @{ DisplayName = 'Toolkit - lawX(lab)+'; WorkspaceName = 'law.(lab)+' } | Should -BeExactly 'Toolkit - lawX(lab)+'
    }

    It 'replaces every occurrence of the workspace resource id, in any case, and nothing else' {
        $json = "{`"fallbackResourceIds`":[`"$($script:wsPath.ToLowerInvariant())`"],`"q`":`"$($script:wsPath.ToUpperInvariant())`",`"other`":`"/subscriptions/x/workspaces/y`"}"
        $result = Invoke-Private ConvertTo-iSOCPortableWorkbookJson @{ Json = $json; WorkspaceResourceId = $script:wsPath }
        ([regex]::Matches($result, 'your-workspace')).Count | Should -Be 2
        $result | Should -Not -Match ([regex]::Escape($script:Sub))
        $result | Should -Match ([regex]::Escape('/subscriptions/x/workspaces/y'))
    }

    It 'handles regex characters in the workspace resource id' {
        Invoke-Private ConvertTo-iSOCPortableWorkbookJson @{ Json = '"/w/a.b+c"'; WorkspaceResourceId = '/w/a.b+c' } | Should -Match 'your-workspace'
        Invoke-Private ConvertTo-iSOCPortableWorkbookJson @{ Json = '"/w/aXb+c"'; WorkspaceResourceId = '/w/a.b+c' } | Should -BeExactly '"/w/aXb+c"'
    }

    Context 'merging metadata' {
        BeforeAll {
            function Merge {
                param([hashtable] $Api = @{}, $Existing)
                $arguments = @{ ApiDisplayName = 'Cost'; ApiDescription = ''; ApiCategory = 'sentinel'; FolderName = 'Cost'; WorkbookId = 'abc'; ExistingMetadata = $Existing }
                foreach ($key in $Api.Keys) { $arguments[$key] = $Api[$key] }
                Invoke-Private Merge-iSOCWorkbookMetadata $arguments
            }
            $script:curated = '{ "displayName": "COST", "description": "Curated.", "category": "Network", "sourceId": "Old", "workbookId": "old", "tags": ["one"] }' | ConvertFrom-Json
        }

        It 'returns the workspace values, in order, when there is no metadata.json (MIGRATION.md edit E26)' {
            $m = Merge -Api @{ ApiDescription = 'From the API.' }
            @($m.Keys) | Should -Be @('displayName', 'description', 'category', 'sourceId', 'workbookId')
            $m.displayName | Should -Be 'Cost'
            $m.description | Should -Be 'From the API.'
            $m.category | Should -Be 'sentinel'
        }

        It 'fills an empty category with sentinel' {
            (Merge -Api @{ ApiCategory = '' }).category | Should -Be 'sentinel'
        }

        It 'keeps a curated description, category and capitalisation' {
            $m = Merge -Existing $script:curated
            $m.description | Should -Be 'Curated.'
            $m.category | Should -Be 'Network'
            $m.displayName | Should -BeExactly 'COST'
        }

        It 'always takes the folder name as the sourceId and the workbook GUID as the workbookId' {
            $m = Merge -Existing $script:curated
            $m.sourceId | Should -Be 'Cost'
            $m.workbookId | Should -Be 'abc'
        }

        It 'takes the workspace''s name when it is a rename, not a change of case' {
            (Merge -Api @{ ApiDisplayName = 'Cost v2' } -Existing $script:curated).displayName | Should -Be 'Cost v2'
        }

        It 'takes the workspace''s description when it has one' {
            (Merge -Api @{ ApiDescription = 'New.' } -Existing $script:curated).description | Should -Be 'New.'
        }

        It 'keeps keys it does not write, after its own, a one-item list as a list' {
            $m = Merge -Existing $script:curated
            @($m.Keys) | Should -Be @('displayName', 'description', 'category', 'sourceId', 'workbookId', 'tags')
            , $m.tags | Should -BeOfType [object[]]
            (ConvertTo-Json -InputObject $m -Compress) | Should -Match '"tags":\["one"\]'
        }
    }
}

Describe 'Playbook helpers (carried over from the unmerged exporter''s suite)' {
    It 'returns <Expected> for a <Type> trigger on <Path>' -ForEach @(
        @{ Type = 'ApiConnectionWebhook'; Kind = $null; Path = '/incident-creation'; Expected = 'Incident' }
        @{ Type = 'ApiConnectionWebhook'; Kind = $null; Path = "/entity/@{encodeURIComponent('Host')}"; Expected = 'Entity' }
        @{ Type = 'ApiConnectionWebhook'; Kind = $null; Path = '/subscribe'; Expected = 'Alert' }
        @{ Type = 'Request'; Kind = 'Http'; Path = $null; Expected = 'Module' }
        @{ Type = 'ApiConnection'; Kind = $null; Path = '/Watchlists/subscriptions/x/watchlists'; Expected = 'Watchlist' }
        @{ Type = 'Recurrence'; Kind = $null; Path = $null; Expected = 'Other' }
    ) {
        $definition = [pscustomobject]@{
            triggers = [pscustomobject]@{ t = [pscustomobject]@{ type = $Type; kind = $Kind; inputs = [pscustomobject]@{ path = $Path } } }
            actions  = [pscustomobject]@{}
        }
        Invoke-Private Get-iSOCPlaybookCategory @{ Definition = $definition } | Should -Be $Expected
    }

    It 'classes a scheduled playbook that edits watchlists as Watchlist' {
        $definition = [pscustomobject]@{
            triggers = [pscustomobject]@{ Recurrence = [pscustomobject]@{ type = 'Recurrence' } }
            actions  = [pscustomobject]@{ Add_item = [pscustomobject]@{ inputs = [pscustomobject]@{ path = '/Watchlists/items' } } }
        }
        Invoke-Private Get-iSOCPlaybookCategory @{ Definition = $definition } | Should -Be 'Watchlist'
    }

    It 'names <LogicAppName> <Expected>' -ForEach @(
        @{ LogicAppName = 'Module-AddSentinelComment'; Expected = 'AddSentinelComment' }
        @{ LogicAppName = 'Incident-DefenderIsolateMachine'; Expected = 'DefenderIsolateMachine' }
        @{ LogicAppName = 'Entity-DefenderRemoveMachineIsolation'; Expected = 'DefenderRemoveMachineIsolation' }
        @{ LogicAppName = 'watchlist-Sync'; Expected = 'Sync' }
        @{ LogicAppName = 'AnalyticResults-Email'; Expected = 'AnalyticResults-Email' }
        @{ LogicAppName = 'Module-'; Expected = 'Module-' }
    ) {
        Invoke-Private Get-iSOCPlaybookFileName @{ LogicAppName = $LogicAppName } | Should -Be $Expected
    }

    It 'singularises portal action names without breaking DNS' {
        $definition = [pscustomobject]@{
            actions = [pscustomobject]@{
                'Entities_-_Get_DNS'        = [pscustomobject]@{}
                'Entities_-_Get_FileHashes' = [pscustomobject]@{}
                'Entities_-_Get_IPs'        = [pscustomobject]@{}
                'Entities_-_Get_Accounts'   = [pscustomobject]@{}
                'Entities_-_Get_Processes'  = [pscustomobject]@{}
                'Entities_-_Get_Files'      = [pscustomobject]@{}
            }
        }
        Invoke-Private Get-iSOCPlaybookEntity @{ Definition = $definition } | Should -Be @('Account', 'DNS', 'File', 'FileHash', 'IP', 'Process')
    }

    It 'reads the entity type from an entity trigger''s path' {
        $definition = [pscustomobject]@{ triggers = [pscustomobject]@{ t = [pscustomobject]@{ inputs = [pscustomobject]@{ path = "/entity/@{encodeURIComponent('Host')}" } } } }
        Invoke-Private Get-iSOCPlaybookEntity @{ Definition = $definition } | Should -Be @('Host')
    }

    It 'finds no entity when none is named' {
        $definition = [pscustomobject]@{ actions = [pscustomobject]@{ Compose = [pscustomobject]@{ type = 'Compose' } } }
        @(Invoke-Private Get-iSOCPlaybookEntity @{ Definition = $definition }).Count | Should -Be 0
    }

    Context 'ARM string values' {
        BeforeEach { $ctx = New-TestContext }

        It 'rewrites a child workflow reference as the existing templates do' {
            $value = "/subscriptions/$($script:Sub)/resourceGroups/rg-automation/providers/Microsoft.Logic/workflows/Module-AddComment"
            Invoke-Private ConvertTo-iSOCArmStringValue @{ Value = $value; Context = $ctx } |
                Should -BeExactly "[concat('/subscriptions/', subscription().subscriptionId, '/resourceGroups/', parameters('AutomationResourceGroup'), '/providers/Microsoft.Logic/workflows/Module-AddComment')]"
            $ctx.UsedParameters | Should -Contain 'AutomationResourceGroup'
        }

        It 'returns a bare expression when the whole value is one id' {
            Invoke-Private ConvertTo-iSOCArmStringValue @{ Value = $script:Sub; Context = $ctx } | Should -BeExactly '[subscription().subscriptionId]'
        }

        It 'parameterises a workspace path, and evaluates back to it' {
            $value = "https://management.azure.com/subscriptions/$($script:Sub)/resourceGroups/rg-sentinel/providers/Microsoft.OperationalInsights/workspaces/law-lab/providers/Microsoft.SecurityInsights/incidents"
            $result = Invoke-Private ConvertTo-iSOCArmStringValue @{ Value = $value; Context = $ctx }
            $result | Should -BeExactly "[concat('https://management.azure.com/subscriptions/', subscription().subscriptionId, '/resourceGroups/', parameters('SentinelResourceGroupName'), '/providers/Microsoft.OperationalInsights/workspaces/', parameters('SentinelWorkpaceName'), '/providers/Microsoft.SecurityInsights/incidents')]"
            Resolve-ArmString -Value $result | Should -BeExactly $value
        }

        It 'doubles single quotes in encodeURIComponent connector paths, and evaluates back' {
            $value = "/Incidents/subscriptions/@{encodeURIComponent('$($script:Sub)')}/resourceGroups/@{encodeURIComponent('rg-sentinel')}/workspaces/@{encodeURIComponent('$($script:WsId)')}/incidents"
            $result = Invoke-Private ConvertTo-iSOCArmStringValue @{ Value = $value; Context = $ctx }
            $result | Should -BeExactly "[concat('/Incidents/subscriptions/@{encodeURIComponent(''', subscription().subscriptionId, ''')}/resourceGroups/@{encodeURIComponent(''', parameters('SentinelResourceGroupName'), ''')}/workspaces/@{encodeURIComponent(''', parameters('WorkspaceId'), ''')}/incidents')]"
            Resolve-ArmString -Value $result | Should -BeExactly $value
            $ctx.UsedParameters | Should -Contain 'WorkspaceId'
        }

        It 'keeps workflow references on AutomationResourceGroup when the playbooks share the workspace''s resource group' {
            $shared = New-TestContext -PlaybookResourceGroup 'rg-sentinel'
            Invoke-Private ConvertTo-iSOCArmStringValue @{ Value = "/subscriptions/$($script:Sub)/resourceGroups/rg-sentinel/providers/Microsoft.Logic/workflows/Module-X"; Context = $shared } |
                Should -Match ([regex]::Escape("parameters('AutomationResourceGroup')"))
            Invoke-Private ConvertTo-iSOCArmStringValue @{ Value = "/subscriptions/$($script:Sub)/resourceGroups/rg-sentinel/providers/Microsoft.OperationalInsights/workspaces/law-lab"; Context = $shared } |
                Should -Match ([regex]::Escape("parameters('SentinelResourceGroupName')"))
        }

        It 'leaves a resource group name in ordinary text alone' {
            Invoke-Private ConvertTo-iSOCArmStringValue @{ Value = 'Escalated by the rg-sentinel team'; Context = $ctx } | Should -BeExactly 'Escalated by the rg-sentinel team'
            $ctx.UsedParameters.Count | Should -Be 0
        }

        It 'escapes a literal ARM would otherwise evaluate' {
            Invoke-Private ConvertTo-iSOCArmStringValue @{ Value = '[1,2,3]'; Context = $ctx } | Should -BeExactly '[[1,2,3]'
        }

        It 'leaves a literal that only starts with a bracket alone' {
            Invoke-Private ConvertTo-iSOCArmStringValue @{ Value = '[note] text'; Context = $ctx } | Should -BeExactly '[note] text'
        }
    }

    Context 'a portable definition' {
        BeforeAll {
            $app = Get-FixtureLogicApp
            $converted = Invoke-Private ConvertTo-iSOCPortableValue @{ Value = $app.properties.definition; Context = (New-TestContext) }
        }

        It 'evaluates every string back to the live value' {
            Compare-PortableRoundTrip -Original $app.properties.definition -Converted $converted | Should -BeNullOrEmpty
        }

        It 'replaces the Azure Monitor Logs query fields by property name' {
            $queries = $converted.actions.Run_query.inputs.queries
            $queries.subscriptions | Should -BeExactly '[subscription().subscriptionId]'
            $queries.resourcegroups | Should -BeExactly "[parameters('SentinelResourceGroupName')]"
            $queries.resourcename | Should -BeExactly "[parameters('SentinelWorkpaceName')]"
            $queries.resourcetype | Should -BeExactly 'Log Analytics Workspace'
        }

        It 'keeps a one-item list as a list' {
            , $converted.actions.Compose_list.inputs | Should -BeOfType [object[]]
            @($converted.actions.Compose_list.inputs).Count | Should -Be 1
        }

        It 'leaves no environment value in the definition' {
            $json = $converted | ConvertTo-Json -Depth 100
            $json | Should -Not -Match $script:Sub
            $json | Should -Not -Match $script:WsId
            $json | Should -Not -Match 'law-lab'
            $json | Should -Not -Match 'resourceGroups/rg-'
        }
    }

    Context 'connections' {
        It 'keeps managed identity only where the live connection used it' {
            $map = Invoke-Private Get-iSOCPlaybookConnectionMap @{ ConnectionsValue = (Get-FixtureLogicApp).properties.parameters.'$connections'.value }
            $map['azuresentinel'].UsesManagedIdentity | Should -BeTrue
            $map['office365'].UsesManagedIdentity | Should -BeFalse
            $map['azuresentinel'].ApiName | Should -Be 'azuresentinel'
        }

        It 'indexes the names of two connections to one API' {
            $value = [pscustomobject]@{ 'azuresentinel' = [pscustomobject]@{ id = '/x/managedApis/azuresentinel' }; 'azuresentinel-1' = [pscustomobject]@{ id = '/x/managedApis/azuresentinel' } }
            $map = Invoke-Private Get-iSOCPlaybookConnectionMap @{ ConnectionsValue = $value }
            $map['azuresentinel'].VariableName | Should -Be 'MicrosoftSentinel0ConnectionName'
            $map['azuresentinel-1'].VariableName | Should -Be 'MicrosoftSentinel1ConnectionName'
        }

        It 'does not index an API connected to once' {
            $map = Invoke-Private Get-iSOCPlaybookConnectionMap @{ ConnectionsValue = (Get-FixtureLogicApp).properties.parameters.'$connections'.value }
            $map['azuresentinel'].VariableName | Should -Be 'MicrosoftSentinelConnectionName'
            $map['office365'].VariableName | Should -Be 'Office365ConnectionName'
            (Invoke-Private Get-iSOCPlaybookConnectionMap @{ ConnectionsValue = [pscustomobject]@{ keyvault = [pscustomobject]@{ id = '/x/managedApis/keyvault' } } })['keyvault'].VariableName | Should -Be 'AzureKeyVaultConnectionName'
        }

        It 'falls back to the reference name without a managed API id' {
            (Invoke-Private Get-iSOCPlaybookConnectionMap @{ ConnectionsValue = [pscustomobject]@{ virustotal_1 = [pscustomobject]@{ connectionId = '/x/connections/vt' } } })['virustotal_1'].ApiName | Should -Be 'virustotal'
        }

        It 'returns an empty map without connections' {
            (Invoke-Private Get-iSOCPlaybookConnectionMap @{ ConnectionsValue = $null }).Count | Should -Be 0
        }
    }

    Context 'the template' {
        BeforeAll {
            $app = Get-FixtureLogicApp
            $template = Invoke-Private ConvertTo-iSOCPlaybookTemplate @{ LogicApp = $app; Category = 'Incident'; PlaybookName = $app.name; AuthorName = 'tester'; Context = (New-TestContext) }
            $arm = ConvertTo-TemplateHashtable -Template $template
            $json = $template | ConvertTo-Json -Depth 100
            $workflow = @($arm.resources | Where-Object { $_.type -eq 'Microsoft.Logic/workflows' })[0]
            $connections = @($arm.resources | Where-Object { $_.type -eq 'Microsoft.Web/connections' })
        }

        It 'meets the invariants Test-PlaybookArm.Tests.ps1 holds the repository to' {
            $arm['$schema'] | Should -Be 'https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#'
            $arm.contentVersion | Should -Not -BeNullOrEmpty
            $arm.parameters.Contains('PlaybookName') | Should -BeTrue
            $workflow.properties.definition.triggers.Keys.Count | Should -BeGreaterThan 0
            $workflow.properties.definition.actions.Keys.Count | Should -BeGreaterThan 0
        }

        It 'keeps the live name as the PlaybookName default and title' {
            $arm.parameters.PlaybookName.defaultValue | Should -Be 'Incident-StandInIsolate'
            $arm.metadata.title | Should -Be 'Incident-StandInIsolate'
        }

        It 'declares every parameter and variable an expression references' {
            foreach ($name in ([regex]::Matches($json, "parameters\('([A-Za-z]+)'\)") | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)) { $arm.parameters.Contains($name) | Should -BeTrue -Because "it references parameters('$name')" }
            foreach ($name in ([regex]::Matches($json, "variables\('([A-Za-z0-9]+)'\)") | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)) { $arm.variables.Contains($name) | Should -BeTrue -Because "it references variables('$name')" }
        }

        It 'gives every connection resource its own name' {
            $names = @($arm.variables.Values)
            ($names | Select-Object -Unique).Count | Should -Be $names.Count
            $connections.Count | Should -Be 2
            @($workflow.dependsOn).Count | Should -Be 2
        }

        It 'writes managed identity for the Sentinel connection only' {
            $value = $workflow.properties.parameters['$connections'].value
            $value.azuresentinel.connectionProperties.authentication.type | Should -Be 'ManagedServiceIdentity'
            $value.office365.Contains('connectionProperties') | Should -BeFalse
            ($connections | Where-Object { $_.properties.api.id -match 'managedApis/azuresentinel' }).properties.parameterValueType | Should -Be 'Alternative'
            ($connections | Where-Object { $_.properties.api.id -match 'managedApis/office365' }).properties.Contains('parameterValueType') | Should -BeFalse
        }

        It 'tags the workflow, fills in the metadata and keeps the live state' {
            $workflow.tags.Source | Should -Be 'Sentinel-As-Code'
            $arm.metadata.tags | Should -Contain 'Incident'
            $arm.metadata.tags | Should -Contain 'Source: Sentinel-As-Code'
            $arm.metadata.entities | Should -Contain 'Host'
            $arm.metadata.author.name | Should -Be 'tester'
            $workflow.properties.state | Should -Be 'Disabled'
        }

        It 'leaves no environment value anywhere in the template' {
            $json | Should -Not -Match $script:Sub
            $json | Should -Not -Match $script:WsId
            $json | Should -Not -Match 'rg-automation'
            $json | Should -Not -Match 'law-lab'
        }

        It 'declares AutomationResourceGroup for a module calling another module' {
            $module = New-LogicApp -Name 'Module-Wrapper' -Triggers @{ manual = @{ type = 'Request'; kind = 'Http' } } -Actions @{ Call = @{ type = 'Workflow'; inputs = @{ host = @{ workflow = @{ id = "$($script:laBase)/Module-Inner" } } } } }
            $moduleArm = ConvertTo-TemplateHashtable -Template (Invoke-Private ConvertTo-iSOCPlaybookTemplate @{ LogicApp = $module; Category = 'Module'; PlaybookName = 'Module-Wrapper'; AuthorName = 'tester'; Context = (New-TestContext) })
            $moduleArm.parameters.Contains('AutomationResourceGroup') | Should -BeTrue
            $moduleArm.parameters.Contains('SentinelWorkpaceName') | Should -BeFalse
            $moduleWorkflow = @($moduleArm.resources | Where-Object { $_.type -eq 'Microsoft.Logic/workflows' })[0]
            $moduleWorkflow.properties.Contains('accessControl') | Should -BeTrue
            $moduleWorkflow.properties.state | Should -Be 'Enabled'
        }
    }

    Context 'plain-text secrets' {
        It 'flags the literal API key header in the fixture' {
            Invoke-Private Find-iSOCPlaintextSecret @{ Node = (Get-FixtureLogicApp).properties.definition } | Should -Be @('actions.Lookup_reputation.inputs.headers.x-apikey')
        }

        It 'flags literal authentication secrets and key-bearing URIs, nested actions included' {
            $definition = [pscustomobject]@{
                actions = [pscustomobject]@{
                    Scope = [pscustomobject]@{
                        actions = [pscustomobject]@{
                            Token = [pscustomobject]@{ inputs = [pscustomobject]@{ authentication = [pscustomobject]@{ type = 'ActiveDirectoryOAuth'; secret = 'abc123' } } }
                            Func  = [pscustomobject]@{ inputs = [pscustomobject]@{ uri = 'https://fn.azurewebsites.net/api/run?code=xyz' } }
                        }
                    }
                }
            }
            $findings = @(Invoke-Private Find-iSOCPlaintextSecret @{ Node = $definition })
            $findings | Should -Contain 'actions.Scope.actions.Token.inputs.authentication.secret'
            $findings | Should -Contain 'actions.Scope.actions.Func.inputs.uri'
            $findings.Count | Should -Be 2
        }

        It 'ignores workflow expressions' {
            $definition = [pscustomobject]@{
                actions = [pscustomobject]@{
                    Http = [pscustomobject]@{
                        inputs = [pscustomobject]@{
                            uri            = "https://fn.azurewebsites.net/api/run?code=@{body('Get_secret')?['value']}"
                            headers        = [pscustomobject]@{ Authorization = "@{body('Get_secret')?['value']}"; 'Content-Type' = 'application/json' }
                            authentication = [pscustomobject]@{ type = 'Basic'; password = "@parameters('Password')" }
                        }
                    }
                }
            }
            @(Invoke-Private Find-iSOCPlaintextSecret @{ Node = $definition }).Count | Should -Be 0
        }
    }
}

Describe 'Export handlers' {
    BeforeAll {
        $script:fixtureRepo = Join-Path $PSScriptRoot 'Fixtures/repo'
        function New-Run {
            param([string] $RepoPath = $script:fixtureRepo, [string[]] $Exclude = @('ContentHub'))
            Invoke-Private New-iSOCDriftRun @{ Context = $script:context; RepoPath = $RepoPath; Options = @{ ExcludeSource = $Exclude } }
        }
        function Get-Source {
            param([string] $Type, [psobject] $Item, [psobject] $Run = (New-Run))
            Invoke-Private Invoke-iSOCContentTypeHandler @{ ContentType = (Get-Type $Type); Handler = 'Classify'; Parameters = @{ Run = $Run; ContentType = (Get-Type $Type); WorkspaceItem = $Item } }
        }
        $script:derived = Invoke-Private Get-iSOCWorkbookResourceName @{ Context = $script:context; FolderName = 'ArmWrapped' }
        $script:pinned = ((Get-Content (Join-Path $script:fixtureRepo 'Content/Workbooks/FixtureOverview/metadata.json') -Raw | ConvertFrom-Json).workbookId)
    }

    Context 'reading the workspace' {
        It 'lists Sentinel workbooks of the workspace with their content, and reads one the list leaves empty on its own' {
            Mock -ModuleName iSOCDeployments Write-iSOCLog { }
            Mock -ModuleName iSOCDeployments Invoke-iSOCRestRequest {
                if ($Path.Contains('/workbooks?')) { return @((New-Workbook -Name 'a' -DisplayName 'A' -SerializedData '{}'), (New-Workbook -Name 'b' -DisplayName 'B' -NoContent), (New-Workbook -Name 'c' -DisplayName 'C' -NoContent)) }
                if ($Path.EndsWith('/b?canFetchContent=true')) { return (New-Workbook -Name 'b' -DisplayName 'B' -SerializedData '{"b":1}') }
                throw 'HTTP 403 - no'
            }
            $items = @(Invoke-Private Read-iSOCWorkbookWorkspace @{ Context = $script:context; ContentType = (Get-Type Workbook) })
            $items.Count | Should -Be 3
            $items[1].properties.serializedData | Should -Be '{"b":1}'
            $items[2].ReadError | Should -Match 'detail fetch failed: HTTP 403'
            Should -Invoke -ModuleName iSOCDeployments Invoke-iSOCRestRequest -ParameterFilter {
                $Path -eq "$($script:wbBase)?category=sentinel&sourceId=$([Uri]::EscapeDataString($script:wsPath))&canFetchContent=true" -and $ApiVersion -eq '2022-04-01'
            } -Times 1 -Exactly
        }

        It 'lists the Logic Apps of the playbook resource group, and reads one without its definition on its own' {
            Mock -ModuleName iSOCDeployments Write-iSOCLog { }
            Mock -ModuleName iSOCDeployments Invoke-iSOCRestRequest {
                if ($Path.Contains('/workflows?')) { return @((New-LogicApp -Name 'x' -Triggers @{ t = @{ type = 'Recurrence' } }), (New-LogicApp -Name 'y' -NoDefinition)) }
                return (New-LogicApp -Name 'y' -Triggers @{ t = @{ type = 'Recurrence' } })
            }
            $items = @(Invoke-Private Read-iSOCPlaybookWorkspace @{ Context = $script:context; ContentType = (Get-Type Playbook) })
            $items.Count | Should -Be 2
            $items[1].properties.definition | Should -Not -BeNullOrEmpty
            Should -Invoke -ModuleName iSOCDeployments Invoke-iSOCRestRequest -ParameterFilter { $Path -eq "$($script:laBase)?`$top=100" -and $ApiVersion -eq '2019-05-01' } -Times 1 -Exactly
        }

        It 'finds the workbooks Content Hub solutions installed, every page of the metadata, and goes on without them when it cannot' {
            Mock -ModuleName iSOCDeployments Write-iSOCLog { }
            Mock -ModuleName iSOCDeployments Invoke-iSOCRestRequest {
                @(
                    [pscustomobject]@{ properties = [pscustomobject]@{ kind = 'Workbook'; parentId = "$($script:wbBase)/hub"; source = [pscustomobject]@{ kind = 'Solution'; name = 'Azure Activity' } } }
                    [pscustomobject]@{ properties = [pscustomobject]@{ kind = 'Workbook'; parentId = "$($script:wbBase)/mine"; source = [pscustomobject]@{ kind = 'LocalWorkspace'; name = 'x' } } }
                    [pscustomobject]@{ properties = [pscustomobject]@{ kind = 'AnalyticsRule'; parentId = 'r'; source = [pscustomobject]@{ kind = 'Solution'; name = 'y' } } }
                )
            }
            $lookup = Invoke-Private Get-iSOCContentHubWorkbookLookup @{ Context = $script:context }
            @($lookup.Keys) | Should -Be @("$($script:wbBase)/hub")
            $lookup["$($script:wbBase.ToUpperInvariant())/HUB"] | Should -Be 'Azure Activity'

            Mock -ModuleName iSOCDeployments Invoke-iSOCRestRequest { throw 'HTTP 403 - no' }
            (Invoke-Private Get-iSOCContentHubWorkbookLookup @{ Context = $script:context }).Count | Should -Be 0
            Should -Invoke -ModuleName iSOCDeployments Write-iSOCLog -ParameterFilter { $Level -eq 'Warning' -and $Message -like '*Could not enumerate Sentinel metadata*' }
        }
    }

    Context 'classifying workbooks' {
        BeforeAll {
            Mock -ModuleName iSOCDeployments Write-iSOCLog { }
            Mock -ModuleName iSOCDeployments Get-iSOCContentHubWorkbookLookup { @{ "$($script:wbBase)/hub" = 'Azure Activity' } }
        }

        It 'governs a workbook by its pinned workbookId' {
            $source = Get-Source Workbook (New-Workbook -Name $script:pinned.ToUpperInvariant() -DisplayName 'Renamed' -SerializedData '{}')
            $source.Source | Should -Be 'Custom'
            $source.SourceRef | Should -Be 'Content/Workbooks/FixtureOverview'
            $source.State | Should -BeNullOrEmpty
        }

        It 'governs a workbook by the GUID deploy derives for a folder without one' {
            (Get-Source Workbook (New-Workbook -Name $script:derived -DisplayName 'Arm Wrapped' -SerializedData '{}')).SourceRef | Should -Be 'Content/Workbooks/ArmWrapped'
        }

        It 'skips a Content Hub workbook, unless Content Hub is included' {
            $hub = New-Workbook -Name 'hub' -DisplayName 'Hub' -SerializedData '{}'
            $source = Get-Source Workbook $hub
            $source.Source | Should -Be 'ContentHub'
            $source.Solution | Should -Be 'Azure Activity'
            $source.State | Should -Be 'Skipped'
            (Get-Source Workbook $hub (New-Run -Exclude @())).State | Should -BeNullOrEmpty
        }

        It 'fails one that could not be read, and skips one with no content or content that is not JSON' {
            $broken = New-Workbook -Name 'n1' -DisplayName 'N1' -NoContent
            $broken | Add-Member -NotePropertyName ReadError -NotePropertyValue 'detail fetch failed: HTTP 500'
            $failed = Get-Source Workbook $broken
            $failed.State | Should -Be 'Failed'
            $failed.Source | Should -Be 'Orphan'
            (Get-Source Workbook (New-Workbook -Name 'n2' -DisplayName 'N2' -NoContent)).Reason | Should -Match 'no serializedData'
            (Get-Source Workbook (New-Workbook -Name 'n3' -DisplayName 'N3' -SerializedData '{not json')).Reason | Should -Match 'does not parse'
        }

        It 'reads the repository and the Content Hub records once per run' {
            $run = New-Run
            foreach ($name in 'p', 'q', 'r') { Get-Source Workbook (New-Workbook -Name $name -DisplayName $name -SerializedData '{}') $run | Out-Null }
            Should -Invoke -ModuleName iSOCDeployments Get-iSOCContentHubWorkbookLookup -Times 1 -Exactly -Scope It
        }
    }

    Context 'classifying playbooks' {
        It 'governs a Logic App by its template''s PlaybookName, in any case' {
            $source = Get-Source Playbook (New-LogicApp -Name 'MODULE-ZULUBASE' -Triggers @{ manual = @{ type = 'Request'; kind = 'Http' } })
            $source.Source | Should -Be 'Custom'
            $source.SourceRef | Should -Be 'Content/Playbooks/Module/ZuluBase.json'
        }

        It 'skips as ambiguous a Logic App two templates name, as five pairs in this repository do' {
            $source = Get-Source Playbook (New-LogicApp -Name 'AzureOpenAIAssistant' -Triggers @{ t = @{ type = 'Recurrence' } }) (New-Run -RepoPath $script:repoRoot)
            $source.State | Should -Be 'Skipped'
            $source.Reason | Should -Match 'Content/Playbooks/Alert/AzureOpenAIAssistant.json and Content/Playbooks/Incident/AzureOpenAIAssistant.json'
        }

        It 'fails one that could not be read and skips one with no definition' {
            $broken = New-LogicApp -Name 'b' -NoDefinition
            $broken | Add-Member -NotePropertyName ReadError -NotePropertyValue 'could not be read: HTTP 500'
            (Get-Source Playbook $broken).State | Should -Be 'Failed'
            (Get-Source Playbook (New-LogicApp -Name 'c' -NoDefinition)).Reason | Should -Be 'no workflow definition returned'
            (Get-Source Playbook (New-LogicApp -Name 'd' -Triggers @{ t = @{ type = 'Recurrence' } })).Source | Should -Be 'Orphan'
        }
    }

    Context 'the files written' {
        It 'writes a workbook''s two files with LF line endings, the metadata merged with the folder''s' {
            Mock -ModuleName iSOCDeployments Write-iSOCLog { }
            $workbook = New-Workbook -Name $script:pinned -DisplayName 'Fixture Overview - law-lab' -SerializedData (New-GalleryTemplate -Title 'Overview' -Workspace)
            $existing = Invoke-Private Read-iSOCRepoItemFile @{ Root = $script:fixtureRepo; RelativePath = 'Content/Workbooks/FixtureOverview'; ContentType = (Get-Type Workbook) }
            $files = Invoke-Private ConvertTo-iSOCWorkbookFile @{ WorkspaceItem = $workbook; Context = $script:context; RelativePath = 'Content/Workbooks/FixtureOverview'; Existing = $existing }
            @($files.Keys) | Should -Be @('workbook.json', 'metadata.json')
            $files['workbook.json'] | Should -Not -Match "`r"
            $files['workbook.json'] | Should -Match 'your-workspace'
            $files['workbook.json'].EndsWith("}`n") | Should -BeTrue
            $metadata = $files['metadata.json'] | ConvertFrom-Json
            $metadata.displayName | Should -Be 'Fixture Overview'
            $metadata.sourceId | Should -Be 'FixtureOverview'
            $metadata.workbookId | Should -Be $script:pinned
        }

        It 'writes a workbook deeper than 32 levels whole (MIGRATION.md edit E26)' {
            $deep = '{"a":' * 40 + '1' + '}' * 40
            $files = Invoke-Private ConvertTo-iSOCWorkbookFile @{ WorkspaceItem = (New-Workbook -Name 'd' -DisplayName 'Deep' -SerializedData $deep); Context = $script:context; RelativePath = 'Content/Workbooks/Deep'; Existing = $null }
            (ConvertTo-ParityJson $files['workbook.json']) | Should -BeExactly (ConvertTo-ParityJson $deep)
        }

        It 'gives a new workbook a folder from its name, and refuses a name with no letters or digits' {
            Invoke-Private Get-iSOCWorkbookRepoPath @{ WorkspaceItem = (New-Workbook -Name 'x' -DisplayName 'Identity Overview - law-lab' -SerializedData '{}'); Context = $script:context } | Should -Be 'Content/Workbooks/IdentityOverview'
            { Invoke-Private Get-iSOCWorkbookRepoPath @{ WorkspaceItem = (New-Workbook -Name 'x' -DisplayName '***' -SerializedData '{}'); Context = $script:context } } | Should -Throw '*no letters or digits*'
        }

        It 'gives a new playbook its trigger''s folder and its name without the prefix, as Bicep unless asked for JSON' {
            Invoke-Private Get-iSOCPlaybookRepoPath @{ WorkspaceItem = (Get-FixtureLogicApp) } | Should -Be 'Content/Playbooks/Incident/StandInIsolate.bicep'
            Invoke-Private Get-iSOCPlaybookRepoPath @{ WorkspaceItem = (Get-FixtureLogicApp); Format = 'Json' } | Should -Be 'Content/Playbooks/Incident/StandInIsolate.json'
        }

        It 'writes a Bicep playbook that deploys what the JSON export deploys (MIGRATION.md edit E48)' {
            Mock -ModuleName iSOCDeployments Write-iSOCLog { }
            $json = Invoke-Private ConvertTo-iSOCPlaybookFile @{ WorkspaceItem = (Get-FixtureLogicApp); Context = $script:context; RelativePath = 'Content/Playbooks/Incident/StandInIsolate.json' }
            $bicep = Invoke-Private ConvertTo-iSOCPlaybookFile @{ WorkspaceItem = (Get-FixtureLogicApp); Context = $script:context; RelativePath = 'Content/Playbooks/Incident/StandInIsolate.bicep' }
            $bicep | Should -Match "(?m)^resource workflow 'Microsoft\.Logic/workflows@2017-07-01' = \{$"
            $bicep | Should -Match '(?m)^  name: PlaybookName$'
            $bicep | Should -Not -Match "`r"
            $bicep.EndsWith("`n") | Should -BeTrue
            $file = Join-Path $TestDrive 'StandInIsolate.bicep'
            [System.IO.File]::WriteAllText($file, $bicep)
            $build = @(Invoke-Private Invoke-iSOCBicep @{ Path = @($file) })[0]
            $build.Errors | Should -BeNullOrEmpty
            $build.Succeeded | Should -BeTrue
            Invoke-Private Compare-iSOCArmTemplate @{ Expected = (Invoke-Private ConvertFrom-iSOCJsonText @{ Text = $json }); Actual = $build.Template } | Should -BeNullOrEmpty
        }

        It 'warns about plain-text secrets in a Bicep playbook too' {
            Mock -ModuleName iSOCDeployments Write-iSOCLog { }
            $warnings = [System.Collections.Generic.List[string]]::new()
            Invoke-Private ConvertTo-iSOCPlaybookFile @{ WorkspaceItem = (Get-FixtureLogicApp); Context = $script:context; RelativePath = 'x.bicep'; Warning = $warnings } | Out-Null
            @($warnings).Count | Should -Be 1
        }

        It 'leaves a Bicep template that would change only in its date as it is' {
            Mock -ModuleName iSOCDeployments Write-iSOCLog { }
            $text = Invoke-Private ConvertTo-iSOCPlaybookFile @{ WorkspaceItem = (Get-FixtureLogicApp); Context = $script:context; RelativePath = 'x.bicep' }
            $old = $text -replace "(?m)^metadata lastUpdateTime = '[^']+'$", "metadata lastUpdateTime = '01-01-2020'"
            $old | Should -Not -BeExactly $text
            Invoke-Private ConvertTo-iSOCPlaybookFile @{ WorkspaceItem = (Get-FixtureLogicApp); Context = $script:context; RelativePath = 'x.bicep'; Existing = $old } | Should -BeExactly $old
            $edited = $old -replace "state: 'Disabled'", "state: 'Enabled'"
            Invoke-Private ConvertTo-iSOCPlaybookFile @{ WorkspaceItem = (Get-FixtureLogicApp); Context = $script:context; RelativePath = 'x.bicep'; Existing = $edited } | Should -BeExactly $text
        }

        It 'adds each plain-text secret to the warnings' {
            Mock -ModuleName iSOCDeployments Write-iSOCLog { }
            $warnings = [System.Collections.Generic.List[string]]::new()
            $text = Invoke-Private ConvertTo-iSOCPlaybookFile @{ WorkspaceItem = (Get-FixtureLogicApp); Context = $script:context; Author = 'tester'; Warning = $warnings }
            @($warnings) | Should -Be @("'Incident-StandInIsolate' holds a plain-text secret at actions.Lookup_reputation.inputs.headers.x-apikey. Move it to Key Vault before committing.")
            $text.EndsWith("`n") | Should -BeTrue
            $text | Should -Not -Match "`r"
        }

        It 'leaves a template that would change only in its date as it is (MIGRATION.md edit E27)' {
            Mock -ModuleName iSOCDeployments Write-iSOCLog { }
            $text = Invoke-Private ConvertTo-iSOCPlaybookFile @{ WorkspaceItem = (Get-FixtureLogicApp); Context = $script:context }
            $old = $text -replace '"lastUpdateTime": "[^"]+"', '"lastUpdateTime": "01-01-2020"'
            Invoke-Private ConvertTo-iSOCPlaybookFile @{ WorkspaceItem = (Get-FixtureLogicApp); Context = $script:context; Existing = $old } | Should -BeExactly $old
            $edited = $old -replace '"state": "Disabled"', '"state": "Enabled"'
            Invoke-Private ConvertTo-iSOCPlaybookFile @{ WorkspaceItem = (Get-FixtureLogicApp); Context = $script:context; Existing = $edited } | Should -BeExactly $text
        }
    }

    Context 'reading, comparing and saving an item''s files' {
        It 'reads a file, a folder''s files in ordinal order, and nothing when there is none' {
            $root = Join-Path $TestDrive 'items'
            New-Item -ItemType Directory -Path (Join-Path $root 'f') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $root 'one.json') -Value 'x' -NoNewline
            Set-Content -LiteralPath (Join-Path $root 'f/b.json') -Value 'b' -NoNewline
            New-Item -ItemType File -Path (Join-Path $root 'f/a.json') | Out-Null
            Invoke-Private Read-iSOCRepoItemFile @{ Root = $root; RelativePath = 'one.json'; ContentType = (Get-Type Playbook) } | Should -BeExactly 'x'
            $folder = Invoke-Private Read-iSOCRepoItemFile @{ Root = $root; RelativePath = 'f'; ContentType = (Get-Type Workbook) }
            @($folder.Keys) | Should -Be @('a.json', 'b.json')
            $folder['a.json'] | Should -BeExactly ''
            Invoke-Private Read-iSOCRepoItemFile @{ Root = $root; RelativePath = 'none'; ContentType = (Get-Type Workbook) } | Should -BeNullOrEmpty
        }

        It 'says Created, Updated or Unchanged, case included, and leaves files the content does not name' {
            Invoke-Private Get-iSOCRepoItemChange @{ Existing = $null; Content = 'a' } | Should -Be 'Created'
            Invoke-Private Get-iSOCRepoItemChange @{ Existing = 'a'; Content = 'A' } | Should -Be 'Updated'
            Invoke-Private Get-iSOCRepoItemChange @{ Existing = 'a'; Content = 'a' } | Should -Be 'Unchanged'
            Invoke-Private Get-iSOCRepoItemChange @{ Existing = [ordered]@{ 'w.json' = 'w'; 'extra' = 'e' }; Content = [ordered]@{ 'w.json' = 'w' } } | Should -Be 'Unchanged'
            Invoke-Private Get-iSOCRepoItemChange @{ Existing = [ordered]@{ 'w.json' = 'w' }; Content = [ordered]@{ 'w.json' = 'w'; 'm.json' = 'm' } } | Should -Be 'Updated'

            $root = Join-Path $TestDrive 'save'
            Invoke-Private Save-iSOCRepoItem @{ Root = $root; RelativePath = 'Content/Workbooks/W'; Content = [ordered]@{ 'w.json' = "w`n" } } | Should -Be 'Created'
            Set-Content -LiteralPath (Join-Path $root 'Content/Workbooks/W/keep.txt') -Value 'k'
            Invoke-Private Save-iSOCRepoItem @{ Root = $root; RelativePath = 'Content/Workbooks/W'; Content = [ordered]@{ 'w.json' = "w`n" } } | Should -Be 'Unchanged'
            Invoke-Private Save-iSOCRepoItem @{ Root = $root; RelativePath = 'Content/Workbooks/W'; Content = [ordered]@{ 'w.json' = "v`n" } } | Should -Be 'Updated'
            Test-Path -LiteralPath (Join-Path $root 'Content/Workbooks/W/keep.txt') | Should -BeTrue
            Invoke-Private Save-iSOCRepoItem @{ Root = $root; RelativePath = 'Content/Playbooks/P.json'; Content = "p`n" } | Should -Be 'Created'
        }
    }

    It 'passes a handler only the parameters it declares' {
        Mock -ModuleName iSOCDeployments Write-iSOCLog { }
        Invoke-Private Invoke-iSOCContentTypeHandler @{ ContentType = (Get-Type Playbook); Handler = 'GetRepoPath'; Parameters = @{ WorkspaceItem = (Get-FixtureLogicApp); Context = $script:context; Unused = 1 } } |
            Should -Be 'Content/Playbooks/Incident/StandInIsolate.bicep'
    }
}

Describe 'Export-iSOCContent' {
    BeforeAll {
        # A small workspace over the fixture repository: one workbook the
        # repository pins, one new, two new with the same name, one whose
        # folder name another folder already has, one Content Hub workbook;
        # one Logic App the repository has, one new, one that cannot be
        # read.
        $script:smallStandIn = @{
            workbooks = @(
                (New-Workbook -Name $script:pinned -DisplayName 'Fixture Overview' -SerializedData (New-GalleryTemplate -Title 'Fixture'))
                (New-Workbook -Name 'aaaaaaaa-0000-0000-0000-000000000001' -DisplayName 'Identity Overview' -SerializedData (New-GalleryTemplate -Title 'Identity'))
                (New-Workbook -Name 'aaaaaaaa-0000-0000-0000-000000000002' -DisplayName 'Twin' -SerializedData (New-GalleryTemplate -Title 'Twin one'))
                (New-Workbook -Name 'aaaaaaaa-0000-0000-0000-000000000003' -DisplayName 'Twin' -SerializedData (New-GalleryTemplate -Title 'Twin two'))
                (New-Workbook -Name 'aaaaaaaa-0000-0000-0000-000000000004' -DisplayName 'No Template' -SerializedData (New-GalleryTemplate -Title 'Not this one'))
                (New-Workbook -Name 'hub' -DisplayName 'Hub Workbook' -SerializedData (New-GalleryTemplate -Title 'Hub'))
            )
            playbooks = @(
                (New-LogicApp -Name 'Module-ZuluBase' -Triggers @{ manual = @{ type = 'Request'; kind = 'Http' } } -Actions @{ Respond = @{ type = 'Response'; inputs = @{ statusCode = 200 } } })
                (Get-FixtureLogicApp)
                (New-LogicApp -Name 'Incident-StandInBroken' -NoDefinition)
            )
        }
        function Invoke-SmallExport {
            param([hashtable] $Parameters = @{}, [string] $RepoPath)
            Mock -ModuleName iSOCDeployments Write-iSOCLog { }
            Mock -ModuleName iSOCDeployments Assert-iSOCPrerequisite { }
            Mock -ModuleName iSOCDeployments Invoke-iSOCRestRequest {
                if ($Path.Contains('/workbooks?')) { return $script:smallStandIn.workbooks }
                if ($Path.Contains('/workflows?')) { return $script:smallStandIn.playbooks }
                if ($Path -like '*/metadata') { return @([pscustomobject]@{ properties = [pscustomobject]@{ kind = 'Workbook'; parentId = "$($script:wbBase)/hub"; source = [pscustomobject]@{ kind = 'Solution'; name = 'Azure Activity' } } }) }
                throw "HTTP 500 - $Path"
            }
            Export-iSOCContent -Context $script:context -RepoPath $RepoPath -Author 'tester' @Parameters
        }
        function New-FixtureCopy {
            $copy = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Fixtures/repo') -Destination $copy -Recurse
            $copy
        }
    }

    It 'accounts for every item, writing only what is new' {
        $copy = New-FixtureCopy
        $run = Invoke-SmallExport -RepoPath $copy
        $outcome = @{}
        foreach ($r in $run.Results) { $outcome["$($r.ContentType)/$($r.Name)/$($r.Identity)"] = "$($r.Outcome): $($r.Reason)" }
        $outcome["Workbook/Fixture Overview/$($script:pinned)"] | Should -Match '^Skipped: already in the repository'
        $outcome['Workbook/Identity Overview/aaaaaaaa-0000-0000-0000-000000000001'] | Should -Be 'Created: '
        $outcome['Workbook/Twin/aaaaaaaa-0000-0000-0000-000000000002'] | Should -Be 'Created: '
        $outcome['Workbook/Twin/aaaaaaaa-0000-0000-0000-000000000003'] | Should -Be "Skipped: the same path as 'Twin'"
        $outcome['Workbook/No Template/aaaaaaaa-0000-0000-0000-000000000004'] | Should -Be 'Skipped: its path already holds another item'
        $outcome['Workbook/Hub Workbook/hub'] | Should -Match '^Skipped: a Content Hub workbook'
        $outcome['Playbook/Module-ZuluBase/Module-ZuluBase'] | Should -Match '^Skipped: already in the repository'
        $outcome['Playbook/Incident-StandInIsolate/Incident-StandInIsolate'] | Should -Be 'Created: '
        $outcome['Playbook/Incident-StandInBroken/Incident-StandInBroken'] | Should -Match '^Failed: could not be read: HTTP 500'
        $run.Created | Should -Be 3
        $run.Skipped | Should -Be 5
        $run.Failed | Should -Be 1
        $run.Warnings | Should -Be 1
        $run.ExitCode | Should -Be 1
        ($run.Results | Where-Object Name -eq 'Incident-StandInIsolate').Warnings | Should -HaveCount 1
        Get-Content (Join-Path $copy 'Content/Workbooks/Twin/workbook.json') -Raw | Should -Match 'Twin one'
        Test-Path (Join-Path $copy 'Content/Playbooks/Incident/StandInIsolate.bicep') | Should -BeTrue
        Test-Path (Join-Path $copy 'Content/Playbooks/Incident/StandInIsolate.json') | Should -BeFalse
    }

    It 'writes a new playbook as JSON with -Format Json, and keeps a JSON playbook the repository has as JSON' {
        $copy = New-FixtureCopy
        $run = Invoke-SmallExport -RepoPath $copy -Parameters @{ ContentType = 'Playbook'; Format = 'Json' }
        ($run.Results | Where-Object Name -eq 'Incident-StandInIsolate').Path | Should -Be 'Content/Playbooks/Incident/StandInIsolate.json'
        $forced = Invoke-SmallExport -RepoPath $copy -Parameters @{ ContentType = 'Playbook'; Force = $true; Name = 'Module-ZuluBase' }
        ($forced.Results | Where-Object Name -eq 'Module-ZuluBase').Path | Should -Be 'Content/Playbooks/Module/ZuluBase.json'
        Test-Path (Join-Path $copy 'Content/Playbooks/Module/ZuluBase.bicep') | Should -BeFalse
    }

    It 'finds nothing more to write when it runs again' {
        $copy = New-FixtureCopy
        Invoke-SmallExport -RepoPath $copy | Out-Null
        $again = Invoke-SmallExport -RepoPath $copy -Parameters @{ Force = $true }
        @($again.Results | Where-Object { $_.Outcome -in 'Created', 'Updated' } | ForEach-Object { $_.Name } | Sort-Object) | Should -Be @('Fixture Overview', 'Module-ZuluBase')
        @($again.Results | Where-Object Outcome -eq 'Unchanged' | ForEach-Object { $_.Name } | Sort-Object) | Should -Be @('Identity Overview', 'Incident-StandInIsolate', 'Twin')
    }

    It 'writes over an item the repository has, in its own file, with -Force' {
        $copy = New-FixtureCopy
        $run = Invoke-SmallExport -RepoPath $copy -Parameters @{ Force = $true; ContentType = 'Workbook'; Name = 'Fixture*' }
        ($run.Results | Where-Object Outcome -eq 'Updated').Path | Should -Be 'Content/Workbooks/FixtureOverview'
        Get-Content (Join-Path $copy 'Content/Workbooks/FixtureOverview/workbook.json') -Raw | Should -Match 'Fixture'
        @($run.Results | Where-Object Outcome -eq 'Skipped' | Where-Object Reason -eq 'not named by -Name').Count | Should -Be 5
    }

    It 'writes under -Path instead, at the same relative paths, still deciding from the repository' {
        $copy = New-FixtureCopy
        $out = Join-Path $TestDrive 'review'
        $run = Invoke-SmallExport -RepoPath $copy -Parameters @{ Path = $out }
        $run.Path | Should -Be $out
        Test-Path (Join-Path $out 'Content/Workbooks/IdentityOverview/metadata.json') | Should -BeTrue
        Test-Path (Join-Path $copy 'Content/Workbooks/IdentityOverview') | Should -BeFalse
        ($run.Results | Where-Object Name -eq 'Fixture Overview').Outcome | Should -Be 'Skipped'
    }

    It 'writes nothing with -WhatIf, and says what it would do' {
        $copy = New-FixtureCopy
        $before = @(Get-TreeFile -Root $copy -Folder 'Content')
        $run = Invoke-SmallExport -RepoPath $copy -Parameters @{ WhatIf = $true; Force = $true }
        @(Get-TreeFile -Root $copy -Folder 'Content') | Should -Be $before
        ($run.Results | Where-Object Name -eq 'Identity Overview').Reason | Should -Be 'would be created'
        ($run.Results | Where-Object Name -eq 'Fixture Overview').Reason | Should -Be 'would be updated'
        $run.WhatIf | Should -Be 5
    }

    It 'exports a Content Hub workbook with -IncludeContentHub' {
        $copy = New-FixtureCopy
        $run = Invoke-SmallExport -RepoPath $copy -Parameters @{ IncludeContentHub = $true; ContentType = 'Workbook' }
        $hub = $run.Results | Where-Object Name -eq 'Hub Workbook'
        $hub.Outcome | Should -Be 'Created'
        $hub.Source | Should -Be 'ContentHub'
    }

    It 'refuses a content type it cannot export' {
        { Invoke-SmallExport -RepoPath (New-FixtureCopy) -Parameters @{ ContentType = 'Parser' } } | Should -Throw '*cannot export Parser*'
    }
}

Describe 'Export-iSOCContent against a workspace built from this repository' {
    BeforeAll {
        # The stand-in workspace. Workbooks: every workbook in the
        # repository as deploy sends it, the workspace's resource id in its
        # fallbackResourceIds and Sentinel Data Lake with the workspace
        # suffix; two new ones, one suffixed; one from Content Hub; one the
        # list leaves empty but that reads on its own; one empty either
        # way; one that is not JSON. Logic Apps: one of each trigger, two
        # connections to one API, a module call, a plain-text key, one the
        # list leaves without its definition, one the repository has, and
        # one two templates in the repository name.
        $repoWorkbooks = @(InModuleScope iSOCDeployments -Parameters @{ R = $script:repoRoot; C = $script:context } {
                param($R, $C)
                Mock Write-iSOCLog { }
                $type = Get-iSOCContentTypeDefinition -Name Workbook
                foreach ($item in Read-iSOCWorkbookRepo -RepoPath $R -ContentType $type) {
                    if (@(Test-iSOCWorkbook -Item $item).Count -eq 0) { [pscustomobject]@{ Item = $item; Request = (ConvertTo-iSOCWorkbookRequest -Item $item -Context $C) } }
                }
            })
        $workbooks = [System.Collections.Generic.List[object]]::new()
        $script:repoWorkbookNames = @{}
        foreach ($entry in $repoWorkbooks) {
            $body = $entry.Request.Body.properties
            $data = $body.serializedData -replace [regex]::Escape('/subscriptions/00000000-0000-0000-0000-000000000000/resourcegroups/your-resource-group/providers/microsoft.operationalinsights/workspaces/your-workspace'), $script:wsPath.ToLowerInvariant()
            $displayName = if ($entry.Item.FolderName -eq 'SentinelDataLake') { "$($body.displayName) - law-lab" } else { $body.displayName }
            $workbooks.Add((New-Workbook -Name $entry.Request.ResourceName -DisplayName $displayName -SerializedData $data -Category $body.category))
            $script:repoWorkbookNames[$entry.Item.FolderName] = $body.displayName
        }
        $workbooks.Add((New-Workbook -Name 'aaaaaaaa-0000-0000-0000-000000000011' -DisplayName 'Identity Overview - law-lab' -SerializedData (New-GalleryTemplate -Title 'Identity' -Workspace) -Description 'Sign-ins at a glance.'))
        $workbooks.Add((New-Workbook -Name 'aaaaaaaa-0000-0000-0000-000000000012' -DisplayName 'Network Map' -SerializedData (New-GalleryTemplate -Title 'Network') -Category 'Network'))
        $workbooks.Add((New-Workbook -Name 'aaaaaaaa-0000-0000-0000-000000000013' -DisplayName 'Azure Activity' -SerializedData (New-GalleryTemplate -Title 'Activity')))
        $workbooks.Add((New-Workbook -Name 'aaaaaaaa-0000-0000-0000-000000000014' -DisplayName 'Detail Only' -NoContent))
        $workbooks.Add((New-Workbook -Name 'aaaaaaaa-0000-0000-0000-000000000015' -DisplayName 'No Content' -NoContent))
        $workbooks.Add((New-Workbook -Name 'aaaaaaaa-0000-0000-0000-000000000016' -DisplayName 'Broken Json' -SerializedData '{not json'))

        $isolate = Get-FixtureLogicApp
        $apps = @(
            $isolate
            (New-LogicApp -Name 'Module-StandInComment' -Triggers @{ manual = @{ type = 'Request'; kind = 'Http' } } -Actions @{ Call = @{ type = 'Workflow'; inputs = @{ host = @{ workflow = @{ id = "$($script:laBase)/Module-StandInInner" }; triggerName = 'manual' } } } })
            (New-LogicApp -Name 'Entity-StandInBlockIp' -Triggers @{ Entity = @{ type = 'ApiConnectionWebhook'; inputs = @{ path = "/entity/@{encodeURIComponent('Ip')}" } } } -Actions @{ 'Entities_-_Get_IPs' = @{ type = 'ApiConnection'; inputs = @{ path = '/entities/ip' } } } -Connections @{ 'office365' = (New-Connection -Api office365); 'office365-1' = (New-Connection -Api office365); 'azuresentinel' = (New-Connection -Api azuresentinel -ManagedIdentity) })
            (New-LogicApp -Name 'Watchlist-StandInSync' -Triggers @{ Recurrence = @{ type = 'Recurrence' } } -Actions @{ Add = @{ type = 'ApiConnection'; inputs = @{ path = '/Watchlists/items' } } })
            (New-LogicApp -Name 'Other-StandInReport' -Triggers @{ Recurrence = @{ type = 'Recurrence' } } -Actions @{ Send = @{ type = 'Http'; inputs = @{ method = 'POST'; uri = 'https://fn.example.net/api/report?code=abc' } } } -State 'Disabled')
        )
        $apps2 = @(
            (New-LogicApp -Name 'Alert-StandInNotify' -Triggers @{ Alert = @{ type = 'ApiConnectionWebhook'; inputs = @{ path = '/subscribe' } } })
            (New-LogicApp -Name 'Incident-StandInDetail' -NoDefinition)
            (New-LogicApp -Name 'Module-AddSentinelComment' -Triggers @{ manual = @{ type = 'Request'; kind = 'Http' } } -Actions @{ Respond = @{ type = 'Response'; inputs = @{ statusCode = 200 } } })
            (New-LogicApp -Name 'AzureOpenAIAssistant' -Triggers @{ Incident = @{ type = 'ApiConnectionWebhook'; inputs = @{ path = '/incident-creation' } } } -Actions @{ Compose = @{ type = 'Compose'; inputs = 'x' } })
        )
        $detail = New-LogicApp -Name 'Incident-StandInDetail' -Triggers @{ Incident = @{ type = 'ApiConnectionWebhook'; inputs = @{ path = '/incident-creation' } } } -Actions @{ Compose = @{ type = 'Compose'; inputs = 'y' } }

        $key = { param([string] $Path) $Path.ToLowerInvariant() }
        $standIn = [ordered]@{
            Context = [ordered]@{ SubscriptionId = $script:Sub; WorkspaceResourceId = $script:wsPath; WorkspaceId = $script:WsId }
            Lists   = [ordered]@{
                (& $key $script:wbBase)                                                     = @(, @($workbooks.ToArray()))
                (& $key "$($script:wsPath)/providers/Microsoft.SecurityInsights/metadata") = @(
                    , @([pscustomobject]@{ properties = [pscustomobject]@{ kind = 'AnalyticsRule'; parentId = 'r'; source = [pscustomobject]@{ kind = 'Solution'; name = 'Azure Activity' } } })
                    , @([pscustomobject]@{ properties = [pscustomobject]@{ kind = 'Workbook'; parentId = "$($script:wbBase)/aaaaaaaa-0000-0000-0000-000000000013"; source = [pscustomobject]@{ kind = 'Solution'; name = 'Azure Activity' } } })
                )
                (& $key $script:laBase)                                                     = @(, $apps; , $apps2)
            }
            Items   = [ordered]@{
                (& $key "$($script:wbBase)/aaaaaaaa-0000-0000-0000-000000000014") = (New-Workbook -Name 'aaaaaaaa-0000-0000-0000-000000000014' -DisplayName 'Detail Only' -SerializedData (New-GalleryTemplate -Title 'Detail'))
                (& $key "$($script:wbBase)/aaaaaaaa-0000-0000-0000-000000000015") = (New-Workbook -Name 'aaaaaaaa-0000-0000-0000-000000000015' -DisplayName 'No Content' -NoContent)
                (& $key "$($script:laBase)/Incident-StandInDetail")              = $detail
            }
            Fail    = @()
        }
        $script:standInPath = Join-Path $TestDrive 'export-standin.json'
        Set-Content -LiteralPath $script:standInPath -Value (ConvertTo-Json -InputObject $standIn -Depth 100)

        function Invoke-ModuleExport {
            param([string] $RepoPath, [hashtable] $Parameters = @{}, [string] $StandInPath = $script:standInPath)
            $script:moduleStandIn = Read-ExportStandIn -Path $StandInPath
            Mock -ModuleName iSOCDeployments Write-iSOCLog { }
            Mock -ModuleName iSOCDeployments Assert-iSOCPrerequisite { }
            Mock -ModuleName iSOCDeployments Invoke-iSOCRestRequest {
                $answer = Get-ExportStandInAnswer -StandIn $script:moduleStandIn -Path $Path
                switch ($answer.Kind) {
                    'Collection' { foreach ($page in $answer.Pages) { foreach ($item in $page) { $item } } }
                    'Object' { $answer.Value }
                    'Error' { throw "HTTP 500 from GET $($answer.Key)" }
                    default { throw "HTTP 404 from GET $($answer.Key)" }
                }
            }
            Export-iSOCContent -Context $script:context -RepoPath $RepoPath -Author 'noodlemctwoodle' @Parameters
        }
    }

    Context 'workbooks new to the repository' {
        BeforeAll {
            $script:moduleW1 = New-RepoCopy -Folder @()
            $script:runW1 = Invoke-ModuleExport -RepoPath $script:moduleW1 -Parameters @{ ContentType = 'Workbook' }
        }

        It 'exercises every case' {
            $script:runW1.ExitCode | Should -Be 0
            ($script:runW1.Created + $script:runW1.Updated + $script:runW1.Unchanged) | Should -Be ($script:repoWorkbookNames.Count + 3)
            $script:runW1.Skipped | Should -Be 3
            $script:runW1.Failed | Should -Be 0
            ($script:runW1.Results | Where-Object Name -eq 'Detail Only').Outcome | Should -Be 'Created'
            ($script:runW1.Results | Where-Object Name -eq 'Identity Overview - law-lab').Path | Should -Be 'Content/Workbooks/IdentityOverview'
        }

        It 'writes metadata.json keys in a set order (MIGRATION.md edit E26)' {
            foreach ($file in @(Get-TreeFile -Root $script:moduleW1 -Folder 'Content/Workbooks' | Where-Object { $_ -like '*/metadata.json' })) {
                @((Get-Content -LiteralPath (Join-Path $script:moduleW1 $file) -Raw | ConvertFrom-Json -AsHashtable).Keys) | Should -Be @('displayName', 'description', 'category', 'sourceId', 'workbookId') -Because $file
            }
        }
    }

    Context 'workbooks the repository has, written over' {
        BeforeAll {
            # The workbooks whose display name makes their own folder name.
            $script:inPlace = @($script:repoWorkbookNames.Keys | Where-Object { (Invoke-Private ConvertTo-iSOCWorkbookFolderName @{ DisplayName = $script:repoWorkbookNames[$_] }) -ceq $_ } | Sort-Object)
            $names = @($script:inPlace | ForEach-Object { $script:repoWorkbookNames[$_] })
            $script:moduleW2 = New-RepoCopy -Folder @('Content/Workbooks')
            $script:runW2 = Invoke-ModuleExport -RepoPath $script:moduleW2 -Parameters @{ ContentType = 'Workbook'; Force = $true; Name = @($names | ForEach-Object { $_; "$_ - law-lab" }) }
        }

        It 'covers workbooks with curated metadata, one pinned and one suffixed' {
            $script:inPlace | Should -Contain 'MicrosoftSentinelCostGbpV2'
            $script:inPlace | Should -Contain 'SentinelDataLake'
            $script:inPlace.Count | Should -BeGreaterOrEqual 4
        }

        It 'writes every one of them, and creates none' {
            ($script:runW2.Created + $script:runW2.Updated + $script:runW2.Unchanged) | Should -Be $script:inPlace.Count
            $script:runW2.Created | Should -Be 0
        }

        It 'keeps the curated values' {
            (Get-Content (Join-Path $script:moduleW2 'Content/Workbooks/Perimeter81/metadata.json') -Raw | ConvertFrom-Json).category | Should -Be 'Network'
        }
    }

    Context 'a workbook whose name makes another folder (MIGRATION.md edit E25)' {
        It 'is written over in its own folder, not a second folder deploying the same workbook' {
            $module = New-RepoCopy -Folder @('Content/Workbooks')
            $run = Invoke-ModuleExport -RepoPath $module -Parameters @{ ContentType = 'Workbook'; Name = 'Detection Engineering Dashboard' }
            ($run.Results | Where-Object Name -eq 'Detection Engineering Dashboard').Reason | Should -Match 'already in the repository'
            $run = Invoke-ModuleExport -RepoPath $module -Parameters @{ ContentType = 'Workbook'; Name = 'Detection Engineering Dashboard'; Force = $true }
            ($run.Results | Where-Object Name -eq 'Detection Engineering Dashboard').Path | Should -Be 'Content/Workbooks/DetectionEngineering'
            Test-Path (Join-Path $module 'Content/Workbooks/DetectionEngineeringDashboard') | Should -BeFalse
        }

        It 'fails when it cannot be read' {
            $raw = Get-Content -LiteralPath $script:standInPath -Raw | ConvertFrom-Json -AsHashtable -Depth 100
            $raw.Fail = @("$($script:wbBase)/aaaaaaaa-0000-0000-0000-000000000014".ToLowerInvariant())
            $path = Join-Path $TestDrive 'standin-fail.json'
            Set-Content -LiteralPath $path -Value (ConvertTo-Json -InputObject $raw -Depth 100)
            $run = Invoke-ModuleExport -RepoPath (New-RepoCopy -Folder @()) -Parameters @{ ContentType = 'Workbook'; Name = 'Detail Only' } -StandInPath $path
            ($run.Results | Where-Object Name -eq 'Detail Only').Outcome | Should -Be 'Failed'
            $run.ExitCode | Should -Be 1
        }

        It 'reads every page of the list' {
            $raw = Get-Content -LiteralPath $script:standInPath -Raw | ConvertFrom-Json -AsHashtable -Depth 100
            $all = @($raw.Lists[$script:wbBase.ToLowerInvariant()][0])
            $raw.Lists[$script:wbBase.ToLowerInvariant()] = @(, @($all[0..1]); , @($all[2..($all.Count - 1)]))
            $path = Join-Path $TestDrive 'standin-pages.json'
            Set-Content -LiteralPath $path -Value (ConvertTo-Json -InputObject $raw -Depth 100)
            $run = Invoke-ModuleExport -RepoPath (New-RepoCopy -Folder @()) -Parameters @{ ContentType = 'Workbook' } -StandInPath $path
            $run.Results.Count | Should -Be $all.Count
        }
    }

    Context 'playbooks' {
        BeforeAll {
            $script:moduleP1 = New-RepoCopy -Folder @('Content/Playbooks')
            $script:runP1 = Invoke-ModuleExport -RepoPath $script:moduleP1 -Parameters @{ ContentType = 'Playbook' }
        }

        It 'exercises every case' {
            $script:runP1.ExitCode | Should -Be 0
            $script:runP1.Created | Should -Be 7
            $script:runP1.Skipped | Should -Be 2
            $script:runP1.Failed | Should -Be 0
            $script:runP1.Warnings | Should -Be 2
            @($script:runP1.Results.Warnings | Where-Object { $_ -match 'plain-text secret' }).Count | Should -Be 2
        }

        It 'writes over the same template with -Force, but not one two templates name (MIGRATION.md edit E25)' {
            $module = New-RepoCopy -Folder @('Content/Playbooks')
            $run = Invoke-ModuleExport -RepoPath $module -Parameters @{ ContentType = 'Playbook'; Force = $true }
            $run.Created + $run.Updated + $run.Unchanged | Should -Be 8
            ($run.Results | Where-Object Name -eq 'AzureOpenAIAssistant').Reason | Should -Match '^ambiguous'
            (Get-Content (Join-Path $module 'Content/Playbooks/Incident/AzureOpenAIAssistant.json') -Raw) | Should -BeExactly (Get-Content (Join-Path $script:repoRoot 'Content/Playbooks/Incident/AzureOpenAIAssistant.json') -Raw)
        }

        It 'leaves a template alone when only its date would change (MIGRATION.md edit E27)' {
            $module = New-RepoCopy -Folder @('Content/Playbooks')
            Invoke-ModuleExport -RepoPath $module -Parameters @{ ContentType = 'Playbook'; Name = 'Module-AddSentinelComment'; Force = $true } | Out-Null
            $file = 'Content/Playbooks/Module/AddSentinelComment.json'
            $path = Join-Path $module $file
            Set-Content -LiteralPath $path -Value ((Get-Content -LiteralPath $path -Raw) -replace '"lastUpdateTime": "[^"]+"', '"lastUpdateTime": "01-01-2020"') -NoNewline
            $run = Invoke-ModuleExport -RepoPath $module -Parameters @{ ContentType = 'Playbook'; Name = 'Module-AddSentinelComment'; Force = $true }
            (Get-Content -LiteralPath (Join-Path $module $file) -Raw) | Should -Match '01-01-2020'
            ($run.Results | Where-Object Name -eq 'Module-AddSentinelComment').Outcome | Should -Be 'Unchanged'
        }
    }
}

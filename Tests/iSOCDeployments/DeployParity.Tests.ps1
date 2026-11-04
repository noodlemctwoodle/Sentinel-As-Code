#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester parity tests: Deploy-iSOCContent against the
    Deploy-CustomContent.ps1 steps and Deploy-DefenderDetections.ps1 it
    replaces, over this repository.

.DESCRIPTION
    Both engines run over a copy of this repository's content,
    dependencies.json and sentinel-deployment.config, against the same
    stand-in workspace: a list of tables that leaves some out (so rules
    deploy disabled and hunting queries are skipped for missing
    dependencies), no watchlists and no functions (so the repository's own
    satisfy them, or not), and a tenant that already has the first five
    Defender detections. The content script's pre-flight step and its
    eight content steps (parsers, watchlists, detections, hunting queries,
    playbooks, workbooks, automation rules and summary rules), and the
    Defender script's deploy step, are lifted out by AST and run with their
    REST and Graph calls and the Az.Resources cmdlets stood in for;
    Deploy-iSOCContent runs with the module's REST client and Az.Resources
    wrappers mocked. The two must send the same ARM requests (path,
    api-version and body) and Graph requests (method, URL and body), run
    the same playbook deployments (every parameter but the timestamped
    deployment name), and count the same outcomes per content type.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCDeployments/DeployParity.Tests.ps1

    Runs the whole suite.

.NOTES
    File:         Tests/iSOCDeployments/DeployParity.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.3.1
    Last Updated: 2026-11-04
    Requires:     PowerShell 7.2+, Pester 5+, powershell-yaml

    The suite goes when Deploy-CustomContent.ps1 and
    Deploy-DefenderDetections.ps1 are removed at cut-over; their captured
    requests are kept as golden files first.
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:repoRoot 'Modules/iSOCDeployments/iSOCDeployments.psd1') -Force
    Import-Module (Join-Path $PSScriptRoot '_helpers/Parity.psm1') -Force
    Import-Module powershell-yaml -ErrorAction Stop

    # A copy, so neither engine writes deployment-state.json into the repository.
    $script:copy = Join-Path $TestDrive 'repo'
    New-Item -ItemType Directory -Path $script:copy | Out-Null
    Copy-Item -LiteralPath (Join-Path $script:repoRoot 'Content') -Destination $script:copy -Recurse
    Copy-Item -LiteralPath (Join-Path $script:repoRoot 'dependencies.json') -Destination $script:copy
    New-Item -ItemType Directory -Path (Join-Path $script:copy 'Deploy/content') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $script:repoRoot 'Deploy/content/sentinel-deployment.config') -Destination (Join-Path $script:copy 'Deploy/content')

    # The stand-in workspace: every table the manifest names except a few.
    $manifest = Get-Content -LiteralPath (Join-Path $script:repoRoot 'dependencies.json') -Raw | ConvertFrom-Json -AsHashtable
    $allTables = @($manifest.dependencies.Values | ForEach-Object { $_['tables'] } | Where-Object { $_ } | Sort-Object -Unique)
    $script:absentTables = @('AuditLogs', 'CommonSecurityLog', 'DeviceProcessEvents')
    $script:standInTables = @($allTables | Where-Object { $_ -notin $script:absentTables })

    $script:workspacePath = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.OperationalInsights/workspaces/ws'
    $script:apiHost = 'https://management.azure.com'

    # The stand-in tenant: the first five Defender detections already exist.
    $detectionFiles = @(Get-ChildItem -LiteralPath (Join-Path $script:copy 'Content/DefenderCustomDetections') -Include '*.yaml', '*.yml' -Recurse -File | Sort-Object FullName)
    $script:tenantRules = @($detectionFiles | Select-Object -First 5 | ForEach-Object {
            $rule = ConvertFrom-Yaml -Yaml (Get-Content -LiteralPath $_.FullName -Raw)
            [pscustomobject]@{ id = "tenant-$($_.BaseName)"; displayName = $rule['displayName'] }
        })

    # --- The script ---------------------------------------------------------
    Import-Module (Join-Path $script:repoRoot 'Tests/_helpers/Import-ScriptFunctions.psm1') -Force
    Import-ScriptFunctions -Path (Join-Path $script:repoRoot 'Deploy/content/Deploy-CustomContent.ps1')
    # Both scripts define Write-DeploymentSummary and Invoke-Main, which
    # neither run here calls.
    Import-ScriptFunctions -Path (Join-Path $script:repoRoot 'Deploy/content/Deploy-DefenderDetections.ps1')
    function Write-PipelineMessage { param($Message, $Level) }
    function Invoke-GraphApi {
        param($Uri, $Method, $Headers, $Body)
        if ($Method -eq 'Get') { return [pscustomobject]@{ value = $script:tenantRules } }
        $script:legacyGraph.Add([pscustomobject]@{ Method = ([string]$Method).ToUpperInvariant(); Uri = $Uri; Body = $Body })
        if ($Method -eq 'Post') { return ($Body | ConvertFrom-Json) }
    }
    $script:DetectionRulesEndpoint = 'https://graph.microsoft.com/beta/security/rules/detectionRules'
    $script:GraphAuthHeader = @{}
    function Invoke-SentinelApi {
        param($Uri, $Method, $Headers, $Body)
        if ($Method -eq 'Get') {
            if ($Uri -like '*/tables?*') { return [pscustomobject]@{ value = @($script:standInTables | ForEach-Object { [pscustomobject]@{ name = $_ } }) } }
            return [pscustomobject]@{ value = @() }
        }
        $script:legacyPuts.Add([pscustomobject]@{ Uri = $Uri; Body = $Body })
    }
    # Stand-ins with the real cmdlets' parameters for everything the script
    # passes them.
    function New-AzResourceGroupDeployment {
        [CmdletBinding()]
        param($Name, $ResourceGroupName, $TemplateFile, $TemplateParameterFile, $AutomationResourceGroup, $SentinelResourceGroup,
            $SentinelResourceGroupName, $PlaybookResourceGroup, $SentinelWorkpaceName, $SentinelWorkspaceName, $SubscriptionId, $WorkspaceId)
        $parameters = [hashtable] $PSBoundParameters
        $parameters.Remove('ErrorAction')
        $script:legacyDeployments.Add($parameters)
    }
    function Test-AzResourceGroupDeployment { }
    $script:BasePath = $script:copy
    $script:ResourceGroup = 'rg'
    $script:Workspace = 'ws'
    $script:WhatIf = $false
    $script:SkipCommunityDetections = $false
    $script:ServerUrl = $script:apiHost
    $script:SubscriptionId = '00000000-0000-0000-0000-000000000000'
    $script:BaseUri = "$($script:apiHost)$($script:workspacePath)"
    $script:AuthHeader = @{}
    $script:SentinelApiVersion = '2025-09-01'
    $script:AlertRuleApiVersion = '2025-07-01-preview'
    $script:SavedSearchApiVersion = '2025-07-01'
    $script:WorkbookApiVersion = '2022-04-01'
    $script:SummaryRuleApiVersion = '2025-07-01'
    $script:Region = 'uksouth'
    $script:WorkspaceResourceId = $script:workspacePath
    $script:WorkspaceId = 'c'
    $script:PlaybookRG = 'rg-playbooks'
    $script:legacyPuts = [System.Collections.Generic.List[object]]::new()
    $script:legacyDeployments = [System.Collections.Generic.List[object]]::new()
    $script:legacyGraph = [System.Collections.Generic.List[object]]::new()
    # The script's top-level initialisers, which the AST import does not run.
    $script:DependencyGraph = @{}
    $script:WorkspaceTables = @()
    $script:WorkspaceWatchlists = @()
    $script:WorkspaceFunctions = @()
    $script:InternalParsers = @()
    $script:InternalWatchlists = @()
    $script:DeploymentState = $null
    $script:DeploymentStatePath = $null

    # The script reads its config from beside itself; give it the copy's.
    $script:DeploymentConfig = Get-Content -LiteralPath (Join-Path $script:copy 'Deploy/content/sentinel-deployment.config') -Raw | ConvertFrom-Json
    $script:SmartDeploymentActive = $false
    Initialize-DeploymentState
    Initialize-DependencyGraph
    Invoke-PreFlightChecks
    $script:legacyCounts = [ordered]@{
        Parser        = Deploy-CustomParsers
        Watchlist     = Deploy-CustomWatchlists
        AnalyticsRule  = Deploy-CustomDetections
        HuntingQuery   = Deploy-CustomHuntingQueries
        Playbook       = Deploy-CustomPlaybooks
        Workbook       = Deploy-CustomWorkbooks
        AutomationRule = Deploy-CustomAutomationRules
        SummaryRule    = Deploy-CustomSummaryRules
    }
    $defender = Deploy-DefenderDetections
    $script:legacyCounts.DefenderDetection = @{ Deployed = $defender.Created + $defender.Updated; Skipped = $defender.Skipped; Failed = $defender.Failed }
    $script:legacyUpdated = $defender.Updated
    Remove-Item -LiteralPath (Join-Path $script:copy 'deployment-state.json') -ErrorAction SilentlyContinue

    # --- The module ---------------------------------------------------------
    $script:modulePuts = [System.Collections.Generic.List[object]]::new()
    $script:moduleDeployments = [System.Collections.Generic.List[object]]::new()
    $script:moduleGraph = [System.Collections.Generic.List[object]]::new()
    $script:context = InModuleScope iSOCDeployments -Parameters @{ W = $script:workspacePath } {
        param($W)
        New-iSOCContext -Value @{
            TenantId = 't'; SubscriptionId = '00000000-0000-0000-0000-000000000000'; ResourceGroup = 'rg'; WorkspaceName = 'ws'
            WorkspaceResourceId = $W; WorkspaceId = 'c'; Region = 'uksouth'; PlaybookResourceGroup = 'rg-playbooks'; Environment = 'AzureCloud'
            IsGov = $false; ArmUrl = 'https://management.azure.com'; GraphUrl = 'https://graph.microsoft.com'; Account = 'a'
        }
    }
    Mock -ModuleName iSOCDeployments Assert-iSOCPrerequisite { }
    Mock -ModuleName iSOCDeployments New-iSOCAzResourceGroupDeployment { $script:moduleDeployments.Add([pscustomobject]@{ Name = $Name; Parameters = $Parameters }) }
    Mock -ModuleName iSOCDeployments Test-iSOCAzResourceGroupDeployment { }
    Mock -ModuleName iSOCDeployments Start-Sleep { }
    Mock -ModuleName iSOCDeployments Write-iSOCLog { }
    Mock -ModuleName iSOCDeployments Invoke-iSOCRestRequest {
        if ($Path -like '/security/*') {
            if ($Method -eq 'GET') { return $script:tenantRules }
            $script:moduleGraph.Add([pscustomobject]@{ Method = $Method; Uri = "https://graph.microsoft.com/$ApiVersion$Path"; Body = $Body })
            if ($Method -eq 'POST') { return [pscustomobject]@{ id = $Body.id } }
            return
        }
        if ($Method -eq 'GET') {
            if ($Path -like '*/tables') { return @($script:standInTables | ForEach-Object { [pscustomobject]@{ name = $_ } }) }
            return
        }
        $script:modulePuts.Add([pscustomobject]@{ Uri = "$($script:apiHost)$Path`?api-version=$ApiVersion"; Body = $Body })
    }
    # The scripts deploy no workspace settings: the pipelines did, in a step
    # of their own (WorkspaceSetting.Tests.ps1 holds the module to it).
    $script:run = Deploy-iSOCContent -Context $script:context -RepoPath $script:copy -ExcludeContentType WorkspaceSetting

    $script:legacyByUri = @{}
    foreach ($put in $script:legacyPuts) { $script:legacyByUri[$put.Uri] = @($script:legacyByUri[$put.Uri] | Where-Object { $_ }) + $put }
    $script:moduleByUri = @{}
    foreach ($put in $script:modulePuts) { $script:moduleByUri[$put.Uri] = @($script:moduleByUri[$put.Uri] | Where-Object { $_ }) + $put }
}

AfterAll {
    Remove-Module iSOCDeployments -ErrorAction SilentlyContinue
}

Describe 'Deploy-iSOCContent against Deploy-CustomContent.ps1' {
    It 'exercises the dependency paths: rules sent disabled and queries skipped' {
        @($script:run.Results | Where-Object { $_.Outcome -eq 'DeployedDisabled' -and $_.Reason -eq 'missing dependencies' }).Count | Should -BeGreaterThan 0
        @($script:run.Results | Where-Object { $_.ContentType -eq 'HuntingQuery' -and $_.Reason -eq 'missing dependencies' }).Count | Should -BeGreaterThan 0
    }

    It 'sends as many requests as the script' {
        $script:modulePuts.Count | Should -Be $script:legacyPuts.Count
    }

    It 'sends to the same paths with the same api-versions' {
        @($script:moduleByUri.Keys | Sort-Object) | Should -Be @($script:legacyByUri.Keys | Sort-Object)
    }

    It 'sends the same body to every path' {
        $different = foreach ($uri in $script:legacyByUri.Keys) {
            $old = @($script:legacyByUri[$uri] | ForEach-Object { ConvertTo-ParityJson $_.Body } | Sort-Object)
            $new = @($script:moduleByUri[$uri] | ForEach-Object { ConvertTo-ParityJson $_.Body } | Sort-Object)
            if (($old -join "`n") -cne ($new -join "`n")) { $uri }
        }
        @($different) | Should -BeNullOrEmpty
    }

    It 'runs the same playbook deployments, apart from the timestamped name' {
        $script:moduleDeployments.Count | Should -Be $script:legacyDeployments.Count
        @($script:moduleDeployments.Name) | Should -Match '^Playbook-.{1,40}-\d{14}$'
        $old = @($script:legacyDeployments | ForEach-Object { $p = @{} + $_; $p.Remove('Name'); ConvertTo-ParityJson $p } | Sort-Object)
        $new = @($script:moduleDeployments | ForEach-Object { ConvertTo-ParityJson $_.Parameters } | Sort-Object)
        ($new -join "`n") | Should -BeExactly ($old -join "`n")
    }

    It 'sends the same Defender detection requests, updating the rules the tenant has' {
        $script:legacyUpdated | Should -Be $script:tenantRules.Count
        $key = { param($Call) "$($Call.Method) $($Call.Uri) $(ConvertTo-ParityJson $Call.Body)" }
        $new = @($script:moduleGraph | ForEach-Object { & $key $_ } | Sort-Object -CaseSensitive)
        $old = @($script:legacyGraph | ForEach-Object { & $key $_ } | Sort-Object -CaseSensitive)
        $new.Count | Should -Be $old.Count
        ($new -join "`n") | Should -BeExactly ($old -join "`n")
    }

    It 'counts the same outcomes for <Type>' -ForEach @(
        @{ Type = 'Parser' }, @{ Type = 'Watchlist' }, @{ Type = 'AnalyticsRule' }, @{ Type = 'HuntingQuery' }
        @{ Type = 'Playbook' }, @{ Type = 'Workbook' }, @{ Type = 'AutomationRule' }, @{ Type = 'SummaryRule' }
        @{ Type = 'DefenderDetection' }
    ) {
        $legacy = $script:legacyCounts[$Type]
        $results = @($script:run.Results | Where-Object ContentType -eq $Type)
        @($results | Where-Object { $_.Outcome -in 'Deployed', 'DeployedDisabled' }).Count | Should -Be $legacy.Deployed
        @($results | Where-Object { $_.Outcome -in 'Skipped', 'Unchanged' }).Count | Should -Be $legacy.Skipped
        @($results | Where-Object { $_.Outcome -eq 'Failed' }).Count | Should -Be $legacy.Failed
    }

    It 'succeeds overall, as the script would have' {
        $script:run.ExitCode | Should -Be 0
    }
}

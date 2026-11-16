#Requires -Version 7.6

<#
.SYNOPSIS
    Collect the Sentinel workspace's inventory into _raw/, one capture at a time.

.DESCRIPTION
    Entry point of the collector. Sets up the run (the window every KQL
    capture reads, the output folder, the Azure scope), writes
    run-context.json, then runs each capture in order. A capture is one
    Invoke-*Capture function under Captures/<Area>; Try-Capture runs it, so a
    capture that fails is recorded and the run carries on. The captures share
    the run's scope and paths through a context hashtable, and the shared
    results through $script: variables. The run ends with the capture summary.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Invoke-iSOCBlueprintCollect.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.2.0
    Last Updated: 2026-11-16
    Component:    iSOC Blueprint, Collector
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.

    Credit and thanks: many of the captures added to match the health
    check (rule effectiveness and run health, hunts, playbook runs, the
    agent heartbeat mix, threat intelligence volumes and indicator
    health, among others) are based on the Sentinel health-check script
    by thinkndle, kindly given to the Sentinel-As-Code project. Thank
    you, thinkndle, for sharing your work so generously; it shaped much
    of the Blueprint's health, coverage and maturity reporting.
#>


function Invoke-iSOCBlueprintCollect {
    <#
    .SYNOPSIS
        Export every Microsoft Sentinel artefact, the supporting Log Analytics
        and DCR layer, subscription context and usage to
        <OutputRoot>/<WorkspaceName>/_raw/.

    .DESCRIPTION
        Read-only inventory tool: no mutation, every call is a GET. Designed
        to run in the daily 'sentinel-blueprint' workflow against a workspace
        under a least-privilege service principal (Microsoft Sentinel Reader
        + Log Analytics Reader + Reader/Monitoring Reader at subscription
        scope). Output is a directory of JSON files that the renderer
        (Invoke-iSOCBlueprintRender) converts into the human report.

        Splitting collector and renderer means the cheap, deterministic
        Markdown step can be re-run any time without touching Azure, and
        Pester fixtures can drive the renderer end to end with no auth.

        The captures use Az.SecurityInsights, Az.OperationalInsights and
        Az.Monitor cmdlets where they exist, and Invoke-SentinelRest
        (Private/Azure/Invoke-SentinelRest.ps1) to fall back to direct REST
        for the documented gaps (CCF connectors, Content Hub, settings, full
        DCR JSON, and so on). Provider API versions are passed per capture
        through Invoke-SentinelRest, so one can be bumped in one place.

        Strict mode is on inside the run. The parameters are those of
        Export-iSOCBlueprintInventory, whose help describes them.

    .PARAMETER SubscriptionId
        Subscription ID containing the Sentinel workspace. Defaults to the active Az context.

    .PARAMETER ResourceGroup
        Resource Group containing the Sentinel workspace.

    .PARAMETER WorkspaceName
        Log Analytics workspace name with Sentinel onboarded.

    .PARAMETER OutputRoot
        Folder root for the export. Defaults to ./SecurityDocs.

    .PARAMETER RunFolder
        A folder under the workspace's folder for this run, such as the date.

    .PARAMETER PlaybookResourceGroup
        Resource group holding the Logic App playbooks, when not the workspace's.

    .PARAMETER IncludePreview
        Use the preview API version where applicable.

    .PARAMETER TargetMaturityLevel
        Maturity level (1 to 5) the workspace is aiming for. Defaults to 3.

    .PARAMETER LookbackDays
        Days of activity every KQL capture reads, 1 to 730 (default 30).

    .PARAMETER Currency
        The currency the cost estimate prices in; Auto takes it from the region.

    .PARAMETER EngineRoot
        The Engine folder, which holds Private/Resources that the Gap, Cost and
        Maturity captures read. Defaults to the module's own.

    .EXAMPLE
        Invoke-iSOCBlueprintCollect -ResourceGroup 'rg-sentinel-prod' -WorkspaceName 'law-sentinel-prod'

        Exports the full inventory to ./SecurityDocs/law-sentinel-prod/_raw/.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$SubscriptionId,

        [Parameter(Mandatory = $true)]
        [string]$ResourceGroup,

        [Parameter(Mandatory = $true)]
        [string]$WorkspaceName,

        [Parameter(Mandatory = $false)]
        [string]$OutputRoot = (Join-Path -Path (Get-Location).ProviderPath -ChildPath 'SecurityDocs'),

        [Parameter(Mandatory = $false)]
        [ValidatePattern('^[\w.-]*$')]
        [string]$RunFolder,

        [Parameter(Mandatory = $false)]
        [string]$PlaybookResourceGroup,

        [Parameter(Mandatory = $false)]
        [switch]$IncludePreview,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 5)]
        [int]$TargetMaturityLevel = 3,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 730)]
        [int]$LookbackDays = 30,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Auto', 'USD', 'AUD', 'BRL', 'CAD', 'CHF', 'CNY', 'DKK', 'EUR', 'GBP', 'INR', 'JPY', 'KRW', 'NOK', 'NZD', 'RUB', 'SEK', 'TWD')]
        [string]$Currency = 'Auto',

        [Parameter(Mandatory = $false)]
        [string]$EngineRoot = $script:iSOCBlueprintEngineRoot
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
    $InformationPreference = 'Continue'

    # One lookback for every KQL capture (see Add-BpWindow). The days the
    # daily series cover: the lookback, at most 90. The dashboard's slider
    # re-scopes its cards to any number of days up to this.
    $script:LookbackDays = $LookbackDays
    $script:RecentDays   = [math]::Min(7, $LookbackDays)
    $script:DailyDays    = [math]::Min(90, $LookbackDays)

    $apiVersions = Get-CollectorApiVersion
    $blueprintVersion = [string](Import-PowerShellDataFile -LiteralPath (Join-Path $EngineRoot '../iSOCBlueprint.psd1')).ModuleVersion

    # Shared between captures: each capture runs in its own scope. The
    # workspace capture sets WorkspaceObject, and a run in which that capture
    # fails must not read the workspace an earlier run in this session left
    # behind, so it is removed (as a fresh script scope had it), not emptied.
    Remove-Variable -Name WorkspaceObject -Scope Script -ErrorAction SilentlyContinue
    $script:AlertRules         = @()
    $script:AlertRuleTemplates = @()
    $script:Workflows          = @()
    $script:GapOutcomes        = $null

    # Add the System.Web assembly for HttpUtility used by Get-AzureRetailPrice.
    Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue

    $workspaceOut = Join-Path $OutputRoot $WorkspaceName
    if ($RunFolder) { $workspaceOut = Join-Path $workspaceOut $RunFolder }
    $rawOut = Join-Path $workspaceOut '_raw'
    $script:RawOut = $rawOut

    if (-not (Test-Path $rawOut)) {
        New-Item -ItemType Directory -Path $rawOut -Force | Out-Null
    }

    $script:CaptureErrors = New-Object System.Collections.Generic.List[pscustomobject]

    $azure = Resolve-CollectorAzureContext -SubscriptionId $SubscriptionId
    $SubscriptionId = $azure.SubscriptionId

    $workspaceResourceId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName"
    $sentinelScope       = "$workspaceResourceId/providers/Microsoft.SecurityInsights"

    $runContext = New-CollectorRunContext -AzureContext $azure.Context -SubscriptionId $SubscriptionId -TenantId $azure.TenantId `
        -ResourceGroup $ResourceGroup -WorkspaceName $WorkspaceName -WorkspaceResourceId $workspaceResourceId `
        -ApiVersions $apiVersions -BlueprintVersion $blueprintVersion -IncludePreview:$IncludePreview -Currency $Currency -EngineRoot $EngineRoot
    Save-Json -FileName 'run-context.json' -Data $runContext

    $context = @{
        apiVersions           = $apiVersions
        Currency              = $Currency
        PlaybookResourceGroup = $PlaybookResourceGroup
        rawOut                = $rawOut
        ResourceGroup         = $ResourceGroup
        sentinelScope         = $sentinelScope
        SubscriptionId        = $SubscriptionId
        TargetMaturityLevel   = $TargetMaturityLevel
        workspaceResourceId   = $workspaceResourceId
        engineRoot            = $EngineRoot
    }

    foreach ($label in $script:CollectorCaptures.Keys) {
        $capture = $script:CollectorCaptures[$label]
        Try-Capture $label { & $capture -Context $context }
    }

    Complete-CollectorRun -RunContext $runContext -RawOut $rawOut
}

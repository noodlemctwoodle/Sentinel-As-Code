#Requires -Version 7.2

<#
.SYNOPSIS
    Export-iSOCBlueprintInventory: collect a workspace into a Blueprint
    inventory.

.DESCRIPTION
    The only step that talks to Azure. Everything else in the module works
    offline from the folder this writes. Runs Engine/Export-SentinelInventory.ps1.

.NOTES
    File:         Modules/iSOCBlueprint/Public/Export-iSOCBlueprintInventory.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-13
    Version:      0.4.0
    Last Updated: 2026-10-14
    Requires:     PowerShell 7.2+

    The collector itself requires Az.Accounts, Az.OperationalInsights,
    Az.Resources, Az.Monitor, Az.SecurityInsights and Az.LogicApp; see
    Test-iSOCBlueprintPrerequisite -Step Collect.

    This file defines functions rather than running. Per-parameter and
    per-example detail lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Export-iSOCBlueprintInventory {
    <#
    .SYNOPSIS
        Collect a workspace's configuration and activity into a Blueprint
        inventory.

    .DESCRIPTION
        Reads the workspace through Azure Resource Manager, its Log
        Analytics data and, where the identity allows, Microsoft Graph, and
        writes one JSON file per capture under
        <OutputPath>/<WorkspaceName>/<yyyy-MM-dd>/_raw/: one folder a day
        (UTC), so a run does not overwrite the last and the dashboard can
        look back day by day. A second run on the same day replaces that
        day. -NoDateFolder writes to <OutputPath>/<WorkspaceName>/_raw/
        instead, as the pipelines do. The gap analysis and the maturity
        assessment run at the end and are saved beside the captures
        (gap-analysis.json, gap-checks.json, maturity.json).

        Sign in with Connect-AzAccount first. Reader on the workspace's
        resource group covers most captures; a capture the identity cannot
        read is recorded as failed and the run carries on.

    .PARAMETER Source
        What to document. 'Sentinel', the default and today the only
        source, reads a Microsoft Sentinel workspace.

    .PARAMETER SubscriptionId
        Subscription that holds the workspace. Defaults to the current Az
        context's subscription.

    .PARAMETER ResourceGroup
        Resource group that holds the workspace.

    .PARAMETER WorkspaceName
        Log Analytics workspace name.

    .PARAMETER PlaybookResourceGroup
        Resource group that holds the playbooks (Logic Apps), when it is not
        the workspace's own. Defaults to ResourceGroup.

    .PARAMETER IncludePreview
        Use the preview API version where one adds data (Content Hub product
        packages, summary rules).

    .PARAMETER TargetMaturityLevel
        Maturity level, 1 to 5, the workspace is aiming for. Sets the gap
        and the roadmap in the maturity assessment. Defaults to 3
        (Established).

    .PARAMETER LookbackDays
        Days of activity every KQL capture reads, 1 to 730. Defaults to 30.
        Incidents, alerts, usage and cost, health, agents and table activity
        all cover this window, and the figures for the latest days within it
        the shorter of 7 days and this. The pages, the dashboard's cards and
        the findings name the window; the cost estimate projects a month
        from it.

    .PARAMETER Currency
        The currency the cost estimate prices in. Auto (the default) takes
        it from the workspace's region (UK regions GBP, EU regions EUR, and
        so on); or one of USD, AUD, BRL, CAD, CHF, CNY, DKK, EUR, GBP, INR,
        JPY, KRW, NOK, NZD, RUB, SEK or TWD. Billing currency follows the
        billing account, not the region, so set it when the guess is wrong.

    .PARAMETER OutputPath
        Folder that holds one folder per workspace. Defaults to
        ./SecurityDocs under the current directory.

    .PARAMETER NoDateFolder
        Write to the workspace's folder itself rather than a folder for the
        day. Each run then replaces the last; the pipelines use it, since
        every pipeline run starts from a clean checkout.

    .OUTPUTS
        [pscustomobject] WorkspaceName, Path (the run's folder) and RawPath
        (its _raw folder). Pipe it to ConvertTo-iSOCBlueprint.

    .EXAMPLE
        Export-iSOCBlueprintInventory -ResourceGroup rg-sentinel -WorkspaceName law-sentinel-prod

        Collects the workspace into ./SecurityDocs/law-sentinel-prod/<today>/_raw/.

    .EXAMPLE
        Export-iSOCBlueprintInventory -ResourceGroup rg-sentinel -WorkspaceName law-sentinel-prod |
            ConvertTo-iSOCBlueprint -Format Markdown

        Collects, then renders the Markdown report beside the inventory.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Sentinel')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(ParameterSetName = 'Sentinel')]
        [ValidateSet('Sentinel')]
        [string] $Source = 'Sentinel',

        [Parameter(ParameterSetName = 'Sentinel')]
        [string] $SubscriptionId,

        [Parameter(Mandatory, ParameterSetName = 'Sentinel')]
        [string] $ResourceGroup,

        [Parameter(Mandatory)]
        [string] $WorkspaceName,

        [Parameter(ParameterSetName = 'Sentinel')]
        [string] $PlaybookResourceGroup,

        [Parameter(ParameterSetName = 'Sentinel')]
        [switch] $IncludePreview,

        [ValidateRange(1, 5)]
        [int] $TargetMaturityLevel = 3,

        [ValidateRange(1, 730)]
        [int] $LookbackDays = 30,

        [ValidateSet('Auto', 'USD', 'AUD', 'BRL', 'CAD', 'CHF', 'CNY', 'DKK', 'EUR', 'GBP', 'INR', 'JPY', 'KRW', 'NOK', 'NZD', 'RUB', 'SEK', 'TWD')]
        [string] $Currency = 'Auto',

        [string] $OutputPath,

        [switch] $NoDateFolder
    )

    $root = Resolve-iSOCBlueprintPath -Path $OutputPath -Default 'SecurityDocs'
    $runFolder = if ($NoDateFolder) { '' } else { Get-iSOCBlueprintRunFolderName }
    $params = @{
        ResourceGroup       = $ResourceGroup
        WorkspaceName       = $WorkspaceName
        OutputRoot          = $root
        TargetMaturityLevel = $TargetMaturityLevel
        LookbackDays        = $LookbackDays
        Currency            = $Currency
    }
    if ($runFolder) { $params.RunFolder = $runFolder }
    Copy-iSOCBlueprintParameter -BoundParameters $PSBoundParameters -Into $params -Name 'SubscriptionId', 'PlaybookResourceGroup'
    if ($IncludePreview) { $params.IncludePreview = $true }

    $null = Invoke-iSOCBlueprintEngine -Script 'Export-SentinelInventory.ps1' -Parameters $params -BoundParameters $PSBoundParameters

    $workspace = Join-Path $root $WorkspaceName
    if ($runFolder) { $workspace = Join-Path $workspace $runFolder }
    [pscustomobject]@{
        PSTypeName    = 'iSOCBlueprint.Inventory'
        WorkspaceName = $WorkspaceName
        Path          = $workspace
        RawPath       = Join-Path $workspace '_raw'
    }
}

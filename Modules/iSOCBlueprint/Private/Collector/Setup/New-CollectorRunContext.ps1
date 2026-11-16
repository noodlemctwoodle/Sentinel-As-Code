#Requires -Version 7.6

<#
.SYNOPSIS
    The run-context record that anchors every output of the run.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Setup/New-CollectorRunContext.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.2
    Last Updated: 2026-11-16
    Component:    iSOC Blueprint, Collector
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>


function New-CollectorRunContext {
    <#
    .SYNOPSIS
        Build the record written to run-context.json when the run starts.

    .DESCRIPTION
        Who ran the collector, against which workspace, with which versions and
        window. The run adds CompletedAtUtc and CaptureIssues when it ends
        (Complete-CollectorRun). The window comes from the $script: values the
        entry point sets.

    .PARAMETER AzureContext
        The active Az context.

    .PARAMETER SubscriptionId
        The subscription the run reads.

    .PARAMETER TenantId
        The tenant of that subscription.

    .PARAMETER ResourceGroup
        The workspace's resource group.

    .PARAMETER WorkspaceName
        The workspace name.

    .PARAMETER WorkspaceResourceId
        The workspace's resource id.

    .PARAMETER ApiVersions
        The API versions the captures use.

    .PARAMETER BlueprintVersion
        The module version.

    .PARAMETER IncludePreview
        Whether the run used the preview API versions.

    .PARAMETER Currency
        The currency setting, Auto or a code.

    .PARAMETER ResourcesFolder
        The module's Resources folder, for the commit the module came from.

    .OUTPUTS
        One [pscustomobject], the content of _raw/run-context.json.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)] $AzureContext,
        [Parameter(Mandatory = $true)] [string]$SubscriptionId,
        [Parameter(Mandatory = $true)] [string]$TenantId,
        [Parameter(Mandatory = $true)] [string]$ResourceGroup,
        [Parameter(Mandatory = $true)] [string]$WorkspaceName,
        [Parameter(Mandatory = $true)] [string]$WorkspaceResourceId,
        [Parameter(Mandatory = $true)] [hashtable]$ApiVersions,
        [Parameter(Mandatory = $true)] [string]$BlueprintVersion,
        [Parameter(Mandatory = $false)] [switch]$IncludePreview,
        [Parameter(Mandatory = $true)] [string]$Currency,
        [Parameter(Mandatory = $true)] [string]$ResourcesFolder
    )

    return [pscustomobject]@{
        SubscriptionId    = $SubscriptionId
        TenantId          = $TenantId
        # Who ran the collector: a user, a service principal or a managed identity.
        Account           = [string]$AzureContext.Account.Id
        AccountType       = [string]$AzureContext.Account.Type
        ResourceGroup     = $ResourceGroup
        WorkspaceName     = $WorkspaceName
        WorkspaceResourceId = $WorkspaceResourceId
        StartedAtUtc      = (Get-Date).ToUniversalTime().ToString('o')
        ApiVersions       = $ApiVersions
        BlueprintVersion = $BlueprintVersion
        AzPSVersion       = (Get-Module -ListAvailable Az.Accounts | Sort-Object Version -Descending | Select-Object -First 1).Version.ToString()
        IncludePreview    = [bool]$IncludePreview
        LookbackDays      = $script:LookbackDays
        RecentDays        = $script:RecentDays
        DailyDays         = $script:DailyDays
        Currency          = $Currency
        ScriptCommit      = $(
            if (Get-Command git -ErrorAction SilentlyContinue) { (& git -C $ResourcesFolder rev-parse HEAD 2>$null) -as [string] } else { $null }
        )
    }
}

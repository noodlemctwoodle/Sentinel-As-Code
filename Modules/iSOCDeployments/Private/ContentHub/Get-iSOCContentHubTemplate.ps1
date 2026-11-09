#Requires -Version 7.6

<#
.SYNOPSIS
    The workspace's Content Hub content templates of some kinds.

.DESCRIPTION
    Replaces the template reads in Deploy-AnalyticsRules, Deploy-Workbooks,
    Get-AutomationRuleStatus and Get-HuntingQueryStatus
    (Deploy/content/Deploy-SentinelContentHub.ps1). Every page is read; the
    automation rule and hunting query reads took the first page only
    (MIGRATION.md edit E20).

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentHub/Get-iSOCContentHubTemplate.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCContentHubTemplate {
    <#
    .SYNOPSIS
        List the content templates of the given kinds.

    .DESCRIPTION
        Filters contentTemplates on properties/contentKind, any of the kinds
        given, and with -ExpandMainTemplate asks for each template's
        mainTemplate. A failed read throws; the callers decide what that
        means.

    .PARAMETER Context
        The workspace context.

    .PARAMETER Kind
        The content kinds: AnalyticsRule, Workbook, WorkbookTemplate,
        AutomationRule, HuntingQuery.

    .PARAMETER ExpandMainTemplate
        Include each template's mainTemplate.

    .OUTPUTS
        [psobject] The templates.

    .EXAMPLE
        Get-iSOCContentHubTemplate -Context $ctx -Kind AnalyticsRule -ExpandMainTemplate
    #>
    [CmdletBinding()]
    [OutputType([psobject])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Context,

        [Parameter(Mandatory)]
        [string[]] $Kind,

        [switch] $ExpandMainTemplate
    )

    $filter = @($Kind | ForEach-Object { "(properties/contentKind eq '$_')" }) -join ' or '
    $path = "$($Context.WorkspaceResourceId)/providers/Microsoft.SecurityInsights/contentTemplates?`$filter=$([uri]::EscapeDataString($filter))"
    if ($ExpandMainTemplate) { $path += '&$expand=properties/mainTemplate' }
    Invoke-iSOCRestRequest -Method GET -Path $path -ApiVersion (Get-iSOCApiVersion SecurityInsights)
}

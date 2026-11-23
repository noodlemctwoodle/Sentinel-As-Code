#Requires -Version 7.6

<#
.SYNOPSIS
    Run a KQL query against a Log Analytics workspace.

.DESCRIPTION
    A thin wrapper over Invoke-AzOperationalInsightsQuery (Az.OperationalInsights),
    which signs in to the query endpoint of the Az sign-in's cloud.

.NOTES
    File:         Modules/iSOCDeployments/Private/Az/Invoke-iSOCAzLogQuery.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Invoke-iSOCAzLogQuery {
    <#
    .SYNOPSIS
        Run a KQL query against a Log Analytics workspace.

    .DESCRIPTION
        Calls Invoke-AzOperationalInsightsQuery, which reaches the query
        endpoint of the Az sign-in's cloud, and stops on the first error. It
        needs Az.OperationalInsights; reading only, it runs under -WhatIf.

    .PARAMETER WorkspaceId
        The workspace's customer id (the context's WorkspaceId).

    .PARAMETER Query
        The KQL.

    .OUTPUTS
        [psobject] The response, whose Results are the rows.

    .EXAMPLE
        (Invoke-iSOCAzLogQuery -WorkspaceId $ctx.WorkspaceId -Query 'Usage | take 1').Results
    #>
    [CmdletBinding()]
    [OutputType([psobject])]
    param(
        [Parameter(Mandatory)]
        [string] $WorkspaceId,

        [Parameter(Mandatory)]
        [string] $Query
    )

    Invoke-AzOperationalInsightsQuery -WorkspaceId $WorkspaceId -Query $Query -ErrorAction Stop
}

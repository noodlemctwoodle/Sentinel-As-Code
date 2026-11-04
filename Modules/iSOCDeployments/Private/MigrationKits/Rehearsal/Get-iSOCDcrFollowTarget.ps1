#Requires -Version 7.2

<#
.SYNOPSIS
    Where to look for the rows a run sends: the destination workspace and a column to find them by.

.DESCRIPTION
    The rule's first Log Analytics destination, read for its customer id,
    and the stream's first string column.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/Rehearsal/Get-iSOCDcrFollowTarget.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.0
    Last Updated: 2026-11-04
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCDcrFollowTarget {
    <#
    .SYNOPSIS
        Where to look for the rows a run sends: the destination workspace
        and a column to find them by.

    .DESCRIPTION
        The rule's first Log Analytics destination is read for its customer
        id (a rule need not have one, and then there is none). The column is
        the stream's first string column, which carries the run marker; with
        none, rows are found by time.

    .PARAMETER Context
        The workspace context.

    .PARAMETER Dcr
        The rule, as ARM returns it.

    .PARAMETER StreamColumn
        The stream's columns.

    .OUTPUTS
        [pscustomobject] WorkspaceId and Column, either of which may be
        missing.

    .EXAMPLE
        Get-iSOCDcrFollowTarget -Context $ctx -Dcr $dcr -StreamColumn $columns
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Context,

        [Parameter(Mandatory)]
        [object] $Dcr,

        [Parameter(Mandatory)]
        [object[]] $StreamColumn
    )

    $workspaceId = $null
    $destinations = Get-iSOCPropertyValue -InputObject $Dcr -Path 'properties.destinations.logAnalytics'
    $first = @($destinations)[0]
    $wsResourceId = [string](Get-iSOCPropertyValue -InputObject $first -Path 'workspaceResourceId')
    if ($wsResourceId -and $wsResourceId -match '/resourceGroups/(?<rg>[^/]+)/.*/workspaces/(?<name>[^/]+)$') {
        $workspace = Invoke-iSOCRestRequest -Method GET -Path $wsResourceId -ApiVersion (Get-iSOCApiVersion OperationalInsights) -Context $Context
        $workspaceId = [string](Get-iSOCPropertyValue -InputObject $workspace -Path 'properties.customerId')
        if (-not $workspaceId) { $workspaceId = $null }
    }

    $stringColumn = $StreamColumn | Where-Object { ([string]$_.type).ToLowerInvariant() -eq 'string' } | Select-Object -First 1
    [pscustomobject]@{
        WorkspaceId = $workspaceId
        Column      = if ($stringColumn) { $stringColumn.name } else { $null }
    }
}

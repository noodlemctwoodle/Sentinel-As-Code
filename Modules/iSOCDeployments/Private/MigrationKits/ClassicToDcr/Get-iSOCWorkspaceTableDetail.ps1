#Requires -Version 7.6

<#
.SYNOPSIS
    Read one workspace table: its sub type, type, plan and columns.

.DESCRIPTION
    A missing sub type or type is Unknown, a missing plan Analytics; a table
    that cannot be read throws.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/ClassicToDcr/Get-iSOCWorkspaceTableDetail.ps1
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

function Get-iSOCWorkspaceTableDetail {
    <#
    .SYNOPSIS
        Read one workspace table: its sub type, type, plan and columns.

    .DESCRIPTION
        One GET of the table. A missing sub type or type is Unknown, a
        missing plan Analytics, missing columns none. A table that cannot be
        read (404 included) throws.

    .PARAMETER Context
        The workspace context.

    .PARAMETER Table
        The table's name.

    .OUTPUTS
        [pscustomobject] Name, SubType, TableType, Plan and Columns.

    .EXAMPLE
        Get-iSOCWorkspaceTableDetail -Context $ctx -Table MyApp_CL
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Context,

        [Parameter(Mandatory)]
        [string] $Table
    )

    $body = Invoke-iSOCRestRequest -Method GET -Path "$($Context.WorkspaceResourceId)/tables/$Table" -ApiVersion (Get-iSOCApiVersion OperationalInsights)
    $subType = [string](Get-iSOCPropertyValue -InputObject $body -Path 'properties.schema.tableSubType')
    $type = [string](Get-iSOCPropertyValue -InputObject $body -Path 'properties.schema.tableType')
    $plan = [string](Get-iSOCPropertyValue -InputObject $body -Path 'properties.plan')
    $columns = Get-iSOCPropertyValue -InputObject $body -Path 'properties.schema.columns'

    [pscustomobject]@{
        Name      = $Table
        SubType   = if ($subType) { $subType } else { 'Unknown' }
        TableType = if ($type) { $type } else { 'Unknown' }
        Plan      = if ($plan) { $plan } else { 'Analytics' }
        Columns   = if ($columns) { @($columns) } else { @() }
    }
}

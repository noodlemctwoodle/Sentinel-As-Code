#Requires -Version 7.2

<#
.SYNOPSIS
    Migrate one classic table to DCR-based, behind ShouldProcess and a confirmation.

.DESCRIPTION
    The Tables API's migrate operation, which cannot be undone; -Force skips
    the confirmation.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/ClassicToDcr/Convert-iSOCClassicTable.ps1
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

function Convert-iSOCClassicTable {
    <#
    .SYNOPSIS
        Migrate one classic table to DCR-based, behind ShouldProcess and a
        confirmation.

    .DESCRIPTION
        POSTs the table's migrate operation. It cannot be undone: the Log
        Analytics agent can no longer write to the table, and Custom Fields
        defined against it stop receiving data. ShouldProcess honours
        -WhatIf; the confirmation that follows is asked even without
        -Confirm, unless -Force.

    .PARAMETER Context
        The workspace context.

    .PARAMETER Table
        The table.

    .PARAMETER Force
        Skip the confirmation.

    .OUTPUTS
        [bool] Whether the migration ran.

    .EXAMPLE
        Convert-iSOCClassicTable -Context $ctx -Table MyApp_CL -Force
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Context,

        [Parameter(Mandatory)]
        [string] $Table,

        [switch] $Force
    )

    $continueQuery = "Migrate $Table in $($Context.WorkspaceName) to a DCR-based table? " +
    'This cannot be undone, and the Log Analytics agent will no longer be able to write to it.'

    if (-not $PSCmdlet.ShouldProcess("$($Context.WorkspaceName)/$Table", 'Migrate classic table to DCR-based (irreversible)')) {
        return $false
    }
    if (-not ($Force -or $PSCmdlet.ShouldContinue($continueQuery, 'Confirm irreversible table migration'))) {
        return $false
    }

    Invoke-iSOCRestRequest -Method POST -Path "$($Context.WorkspaceResourceId)/tables/$Table/migrate" -ApiVersion (Get-iSOCApiVersion OperationalInsights) | Out-Null
    $true
}

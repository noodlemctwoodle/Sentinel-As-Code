#Requires -Version 7.2

<#
.SYNOPSIS
    Builds the ARM path of the Log Analytics workspace.

.NOTES
    File:         Content/Workbooks/SentinelDataLake/SdlMigrationExport/Private/Azure/Get-SdlBaseUri.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.2.0
    Last Updated: 2026-11-16
    Requires:     PowerShell 7.2+

    Defines one function, dot-sourced by Export-SdlMigrationWorkbook.ps1
    (deprecated; to be replaced by the iSOCDeployments module).
#>

# Keeps the file help above from being read as the help of the function below.

function Get-SdlBaseUri {
    <#
    .SYNOPSIS
        Builds the ARM path of the Log Analytics workspace.

    .DESCRIPTION
        Relative ARM path for the workspace named in the connection
        object, used as the prefix of every ARM call.

    .PARAMETER Connection
        The connection object built by Export-SdlMigrationWorkbook.ps1
        (subscription, resource group, workspace, throttle, API
        versions).

    .OUTPUTS
        [string] The relative ARM path.
    #>
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [object]$Connection
    )

    return "/subscriptions/$($Connection.SubscriptionId)/resourceGroups/$($Connection.ResourceGroupName)/providers/Microsoft.OperationalInsights/workspaces/$($Connection.WorkspaceName)"
}

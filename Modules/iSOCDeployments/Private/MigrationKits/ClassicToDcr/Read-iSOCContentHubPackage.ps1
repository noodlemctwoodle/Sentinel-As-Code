#Requires -Version 7.2

<#
.SYNOPSIS
    Read the workspace's Content Hub catalogue.

.DESCRIPTION
    The contentProductPackages, which say for each solution whether it is
    installed and which data connectors it carries.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/ClassicToDcr/Read-iSOCContentHubPackage.ps1
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

function Read-iSOCContentHubPackage {
    <#
    .SYNOPSIS
        Read the workspace's Content Hub catalogue.

    .DESCRIPTION
        Lists contentProductPackages: each solution's display name,
        installed version and dependencies, which carry its data
        connectors. A failure throws.

    .PARAMETER Context
        The workspace context.

    .OUTPUTS
        [psobject[]] The packages.

    .EXAMPLE
        $packages = @(Read-iSOCContentHubPackage -Context $ctx)
    #>
    [CmdletBinding()]
    [OutputType([psobject[]])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Context
    )

    Invoke-iSOCRestRequest -Method GET -Path "$($Context.WorkspaceResourceId)/providers/Microsoft.SecurityInsights/contentProductPackages" -ApiVersion (Get-iSOCApiVersion SecurityInsights)
}

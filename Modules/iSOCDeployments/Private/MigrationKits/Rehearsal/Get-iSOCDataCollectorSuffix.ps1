#Requires -Version 7.6

<#
.SYNOPSIS
    The Data Collector API host suffix for the Az sign-in's cloud.

.DESCRIPTION
    ods.opinsights.azure.com, .us for US Government, .cn for China.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/Rehearsal/Get-iSOCDataCollectorSuffix.ps1
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

function Get-iSOCDataCollectorSuffix {
    <#
    .SYNOPSIS
        The Data Collector API host suffix for the Az sign-in's cloud.

    .DESCRIPTION
        ods.opinsights.azure.com in the public cloud,
        ods.opinsights.azure.us in US Government and
        ods.opinsights.azure.cn in China.

    .PARAMETER Context
        The workspace context.

    .OUTPUTS
        [string]

    .EXAMPLE
        Get-iSOCDataCollectorSuffix -Context $ctx
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Context
    )

    switch ($Context.Environment) {
        'AzureUSGovernment' { 'ods.opinsights.azure.us' }
        'AzureChinaCloud' { 'ods.opinsights.azure.cn' }
        default { 'ods.opinsights.azure.com' }
    }
}

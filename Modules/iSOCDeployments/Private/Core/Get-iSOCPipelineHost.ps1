#Requires -Version 7.2

<#
.SYNOPSIS
    Which pipeline host, if any, the module is running under.

.NOTES
    File:         Modules/iSOCDeployments/Private/Core/Get-iSOCPipelineHost.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-23
    Version:      0.1.0
    Last Updated: 2026-10-23
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCPipelineHost {
    <#
    .SYNOPSIS
        Name the pipeline host from the variables each one sets.

    .DESCRIPTION
        Azure DevOps sets TF_BUILD (and BUILD_BUILDID, which the scripts this
        module replaces looked for); GitHub Actions sets GITHUB_ACTIONS.
        Anything else is a local console.

    .OUTPUTS
        [string] AzureDevOps, GitHubActions or Local.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if ($env:TF_BUILD -eq 'True' -or $env:BUILD_BUILDID) { return 'AzureDevOps' }
    if ($env:GITHUB_ACTIONS -eq 'true') { return 'GitHubActions' }
    'Local'
}

#Requires -Version 7.6

<#
.SYNOPSIS
    Serialise a solution's packaged content into an ARM deployment request
    body.

.DESCRIPTION
    Copied from ConvertTo-SolutionDeploymentJson
    (Deploy/content/Deploy-SentinelContentHub.ps1).

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentHub/ConvertTo-iSOCSolutionDeploymentJson.ps1
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

function ConvertTo-iSOCSolutionDeploymentJson {
    <#
    .SYNOPSIS
        Return the deployment body as compact JSON.

    .DESCRIPTION
        An incremental deployment of the package with the workspace name and
        region as its parameters. The JSON is compact, with enums as text and
        non-ASCII characters escaped: indentation makes a large solution
        about half as big again (Microsoft Defender XDR 3.2.2 is 5.34 MB
        indented against 3.44 MB compact), and ARM rejects a request over
        4 MB. The string is sent as it is, so its size is the request's.

    .PARAMETER PackagedContent
        The package's template, from its catalogue entry.

    .PARAMETER Workspace
        The workspace name.

    .PARAMETER Region
        The workspace's region.

    .OUTPUTS
        [string]

    .EXAMPLE
        ConvertTo-iSOCSolutionDeploymentJson -PackagedContent $package -Workspace $ctx.WorkspaceName -Region $ctx.Region
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [object] $PackagedContent,

        [Parameter(Mandatory)]
        [string] $Workspace,

        [Parameter(Mandatory)]
        [string] $Region
    )

    $deploymentBody = @{
        properties = @{
            parameters = @{
                'workspace'          = @{ value = $Workspace }
                'workspace-location' = @{ value = $Region }
            }
            template   = $PackagedContent
            mode       = 'Incremental'
        }
    }

    $deploymentBody | ConvertTo-Json -EnumsAsStrings -Depth 50 -EscapeHandling EscapeNonAscii -Compress
}

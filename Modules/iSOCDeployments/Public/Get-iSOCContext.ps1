#Requires -Version 7.2

<#
.SYNOPSIS
    Get-iSOCContext: the workspace the module is connected to.

.NOTES
    File:         Modules/iSOCDeployments/Public/Get-iSOCContext.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-23
    Version:      0.1.0
    Last Updated: 2026-10-23
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter and
    per-example detail lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCContext {
    <#
    .SYNOPSIS
        Return the context the last Connect-iSOCWorkspace set.

    .DESCRIPTION
        Commands use this context when they are not given -Context. Returns
        nothing when no workspace has been connected in this session.

    .OUTPUTS
        [pscustomobject] The iSOCDeployments.Context, or nothing.

    .EXAMPLE
        if (-not (Get-iSOCContext)) { Connect-iSOCWorkspace -ResourceGroup rg-sentinel -WorkspaceName law-sentinel }

        Connects only when no workspace is connected yet.
    #>
    [CmdletBinding()]
    [OutputType('iSOCDeployments.Context')]
    param()

    if ($script:iSOCContext) { $script:iSOCContext }
}

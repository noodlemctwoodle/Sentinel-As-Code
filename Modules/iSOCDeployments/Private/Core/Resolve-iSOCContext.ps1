#Requires -Version 7.6

<#
.SYNOPSIS
    Pick the context a command runs against.

.NOTES
    File:         Modules/iSOCDeployments/Private/Core/Resolve-iSOCContext.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-23
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Resolve-iSOCContext {
    <#
    .SYNOPSIS
        Return the context passed in, else the one Connect-iSOCWorkspace set.

    .PARAMETER Context
        A context from Connect-iSOCWorkspace. Anything else is refused.

    .OUTPUTS
        [pscustomobject] The iSOCDeployments.Context to use.

    .EXAMPLE
        $ctx = Resolve-iSOCContext -Context $Context
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [psobject] $Context
    )

    if ($Context) {
        if ($Context.PSObject.TypeNames -notcontains 'iSOCDeployments.Context') {
            throw '-Context must be the object Connect-iSOCWorkspace returns.'
        }
        return $Context
    }
    if ($script:iSOCContext) { return $script:iSOCContext }
    throw 'No workspace is connected. Run Connect-iSOCWorkspace first, or pass -Context.'
}

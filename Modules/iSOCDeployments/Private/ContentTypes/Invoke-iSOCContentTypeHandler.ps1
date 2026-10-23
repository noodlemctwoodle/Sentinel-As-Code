#Requires -Version 7.2

<#
.SYNOPSIS
    Call one of a content type's handlers.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/Invoke-iSOCContentTypeHandler.ps1
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

function Invoke-iSOCContentTypeHandler {
    <#
    .SYNOPSIS
        Run the function a content type names for a handler.

    .DESCRIPTION
        Handlers are named functions, looked up when they are called, so a
        test can mock any one of them by name and the engines never hold a
        reference to a type's code.

    .PARAMETER ContentType
        The content type.

    .PARAMETER Handler
        The handler: ReadRepo, Validate, ToRequest, GetQuery and the rest
        listed in Docs/Modules/iSOCDeployments/Architecture.md.

    .PARAMETER Parameters
        The handler's parameters, by name.

    .OUTPUTS
        Whatever the handler returns.

    .EXAMPLE
        Invoke-iSOCContentTypeHandler -ContentType $type -Handler ReadRepo -Parameters @{ RepoPath = $repo; ContentType = $type }
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [psobject] $ContentType,

        [Parameter(Mandatory)]
        [string] $Handler,

        [hashtable] $Parameters = @{}
    )

    $command = $ContentType.Handlers[$Handler]
    if (-not $command) { throw "Content type '$($ContentType.Name)' has no $Handler handler." }
    & $command @Parameters
}

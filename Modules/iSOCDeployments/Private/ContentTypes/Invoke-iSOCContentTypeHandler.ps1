#Requires -Version 7.6

<#
.SYNOPSIS
    Call one of a content type's handlers.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/Invoke-iSOCContentTypeHandler.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-23
    Version:      0.2.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

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
        The parameters on offer, by name. Only those the handler declares
        are passed, so a caller can offer what it has (the context, the
        run) and each handler takes what it needs.

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
    $declared = (Get-Command -Name $command -ErrorAction Stop).Parameters
    $arguments = @{}
    foreach ($key in $Parameters.Keys) {
        if ($declared.ContainsKey($key)) { $arguments[$key] = $Parameters[$key] }
    }
    & $command @arguments
}

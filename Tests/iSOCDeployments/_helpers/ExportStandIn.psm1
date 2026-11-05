#Requires -Version 7.2

<#
.SYNOPSIS
    A stand-in workspace for the export tests.

.DESCRIPTION
    Tests/iSOCDeployments/Export.Tests.ps1 writes the stand-in as a JSON
    file: the workspace's identifiers (Context), the collections it lists
    (Lists, each a list of pages), the resources it returns one at a time
    (Items) and the paths whose reads fail (Fail), all keyed by ARM path in
    lower case without a query.

    The module reads it through a mock of Invoke-iSOCRestRequest, which gets
    every page of a collection at once, as the module's client returns them.
    Each run reads the file afresh, so no run sees another's changes.

.NOTES
    File:         Tests/iSOCDeployments/_helpers/ExportStandIn.psm1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.2.0
    Last Updated: 2026-11-05
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Keeps the file help above from being read as the help of the function below.

function Read-ExportStandIn {
    <#
    .SYNOPSIS
        Read the stand-in file.

    .PARAMETER Path
        The JSON file.

    .OUTPUTS
        [pscustomobject] Context, Lists, Items and Fail.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string] $Path
    )

    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 100
}

function Get-ExportStandInAnswer {
    <#
    .SYNOPSIS
        Answer one GET.

    .PARAMETER StandIn
        From Read-ExportStandIn.

    .PARAMETER Path
        The request's path or URL, with or without a query.

    .OUTPUTS
        [pscustomobject] Kind (Collection, Object, Error or Missing), Key,
        Pages for a collection and Value for an object.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [psobject] $StandIn,
        [Parameter(Mandatory)] [string] $Path
    )

    $key = (($Path -replace '^https://[^/]+', '') -split '\?')[0].ToLowerInvariant()
    if (@($StandIn.Fail) -contains $key) { return [pscustomobject]@{ Kind = 'Error'; Key = $key } }
    $list = $StandIn.Lists.PSObject.Properties[$key]
    if ($list) { return [pscustomobject]@{ Kind = 'Collection'; Key = $key; Pages = @($list.Value) } }
    $item = $StandIn.Items.PSObject.Properties[$key]
    if ($item) { return [pscustomobject]@{ Kind = 'Object'; Key = $key; Value = $item.Value } }
    [pscustomobject]@{ Kind = 'Missing'; Key = $key }
}

Export-ModuleMember -Function Read-ExportStandIn, Get-ExportStandInAnswer

#Requires -Version 7.2

<#
.SYNOPSIS
    A stand-in workspace for the export parity tests.

.DESCRIPTION
    Tests/iSOCDeployments/Export.Tests.ps1 writes the stand-in as a JSON
    file: the workspace's identifiers (Context), the collections it lists
    (Lists, each a list of pages), the resources it returns one at a time
    (Items) and the paths whose reads fail (Fail), all keyed by ARM path in
    lower case without a query.

    The module reads it through a mock of Invoke-iSOCRestRequest, which gets
    every page of a collection at once, as the module's client returns them.
    The old export scripts run in a child pwsh against a Sentinel.Common of
    New-ExportLegacyCommon's making, whose Invoke-SentinelApi serves one page
    at a time with a nextLink, as the service does. Both engines read the
    file afresh, so neither sees the other's changes.

.NOTES
    File:         Tests/iSOCDeployments/_helpers/ExportStandIn.psm1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.0
    Last Updated: 2026-11-03
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

function New-ExportLegacyCommon {
    <#
    .SYNOPSIS
        Write a Sentinel.Common stand-in an old export script imports.

    .DESCRIPTION
        Write-PipelineMessage writes to the host; Connect-AzureEnvironment
        returns the stand-in's identifiers; Invoke-SentinelApi answers from
        the stand-in, a collection one page at a time with a nextLink of
        ?page=<n>, and throws as the service would for a failed or missing
        path. The stand-in file and this helper are found through the
        ISOC_EXPORT_STANDIN and ISOC_EXPORT_HELPER environment variables.

    .PARAMETER Folder
        The Modules/Sentinel.Common folder to write.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Writes a test fixture into TestDrive.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Folder
    )

    New-Item -ItemType Directory -Path $Folder -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $Folder 'Sentinel.Common.psd1') -Value "@{ RootModule = 'Sentinel.Common.psm1'; ModuleVersion = '0.0.1'; GUID = '$([guid]::NewGuid())'; FunctionsToExport = '*' }"
    Set-Content -LiteralPath (Join-Path $Folder 'Sentinel.Common.psm1') -Value @'
Import-Module $env:ISOC_EXPORT_HELPER -Force
$script:standIn = Read-ExportStandIn -Path $env:ISOC_EXPORT_STANDIN

function Write-PipelineMessage {
    param([string] $Message, [string] $Level = 'Info')
    Write-Host "[$Level] $Message"
}

function Connect-AzureEnvironment {
    param($ResourceGroup, $Workspace, $Region, $SubscriptionId, [switch] $IsGov, $PlaybookResourceGroup)
    $c = $script:standIn.Context
    @{ SubscriptionId = $c.SubscriptionId; ServerUrl = 'https://management.azure.com'; WorkspaceResourceId = $c.WorkspaceResourceId; WorkspaceId = $c.WorkspaceId; AuthHeader = @{} }
}

function Invoke-SentinelApi {
    param($Uri, $Method, $Headers, $Body)
    $answer = Get-ExportStandInAnswer -StandIn $script:standIn -Path $Uri
    switch ($answer.Kind) {
        'Collection' {
            $page = if ($Uri -match '[?&]page=(\d+)') { [int]$Matches[1] } else { 0 }
            $result = [ordered]@{ value = @($answer.Pages[$page]) }
            if ($page + 1 -lt $answer.Pages.Count) { $result.nextLink = "https://management.azure.com$($answer.Key)?page=$($page + 1)" }
            [pscustomobject]$result
        }
        'Object' { $answer.Value }
        'Error' { throw "Response status code does not indicate success: 500 (Internal Server Error). $($answer.Key)" }
        default { throw "Response status code does not indicate success: 404 (Not Found). $($answer.Key)" }
    }
}
'@
}

Export-ModuleMember -Function Read-ExportStandIn, Get-ExportStandInAnswer, New-ExportLegacyCommon

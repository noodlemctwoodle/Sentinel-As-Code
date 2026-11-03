#Requires -Version 7.2

<#
.SYNOPSIS
    ToRequest handler for workbooks: the body deploy sends.

.DESCRIPTION
    Copied from the body builder inside Deploy-CustomWorkbooks
    (Deploy/content/Deploy-CustomContent.ps1), unchanged in what it sends,
    including the workbookId it derives when metadata.json has none, but
    for the display name a folder gives when metadata has none: the script
    split it between every pair of letters, and here it is split only where
    a capital follows a small letter (MIGRATION.md edit E16).
    Tests/iSOCDeployments/DeployParity.Tests.ps1 holds every workbook in
    Content/Workbooks/ to the request the script builds.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/Workbook/ConvertTo-iSOCWorkbookRequest.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.2.0
    Last Updated: 2026-11-03
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function ConvertTo-iSOCWorkbookRequest {
    <#
    .SYNOPSIS
        Build the workbook request body for one folder.

    .DESCRIPTION
        The display name, category and workbookId come from metadata.json
        when it sets them; otherwise the folder name split at its capitals,
        'sentinel', and a GUID made from the first 16 bytes of the SHA-256
        of '<workspace resource id>-<folder name>', so a workbook keeps its
        name across runs. A gallery template is sent as it is; an ARM
        template wrapping a Microsoft.Insights/workbooks resource sends that
        resource's serializedData instead. A template that does not parse is
        sent as it is, with a warning. The function sends nothing.

    .PARAMETER Item
        A repository item from Read-iSOCWorkbookRepo that passed
        Test-iSOCWorkbook.

    .PARAMETER Context
        The workspace context; its region and workspace resource id go into
        the body.

    .OUTPUTS
        [pscustomobject] iSOCDeployments.Request: ContentType, Identity,
        ResourceName (the workbookId) and Body.

    .EXAMPLE
        $request = ConvertTo-iSOCWorkbookRequest -Item $item -Context $context
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Item,

        [Parameter(Mandatory)]
        [psobject] $Context
    )

    $folderName = $Item.FolderName
    $displayName = $folderName -creplace '([a-z])([A-Z])', '$1 $2'
    $workbookId = $null
    $category = 'sentinel'
    $metadata = $Item.Data
    if ($null -ne $metadata) {
        $value = Get-iSOCPropertyValue -InputObject $metadata -Path 'displayName'
        if ($value) { $displayName = $value }
        $value = Get-iSOCPropertyValue -InputObject $metadata -Path 'workbookId'
        if ($value) { $workbookId = $value }
        $value = Get-iSOCPropertyValue -InputObject $metadata -Path 'category'
        if ($value) { $category = $value }
    }

    if (-not $workbookId) { $workbookId = Get-iSOCWorkbookResourceName -Context $Context -FolderName $folderName }

    $workbookContent = Get-Content -LiteralPath $Item.WorkbookPath -Raw
    $serializedData = $workbookContent
    try {
        $parsedWorkbook = $workbookContent | ConvertFrom-Json -ErrorAction Stop
        if ($parsedWorkbook.PSObject.Properties['resources']) {
            $resource = @($parsedWorkbook.resources) | Where-Object { $_.type -match 'workbooks$' } | Select-Object -First 1
            $inner = Get-iSOCPropertyValue -InputObject $resource -Path 'properties.serializedData'
            if ($inner) {
                $serializedData = $inner
                Write-iSOCLog "ARM-wrapped workbook detected for '$folderName'; extracted inner serializedData."
            }
            else {
                Write-iSOCLog "Workbook '$folderName' has a top-level 'resources' array but no Microsoft.Insights/workbooks serializedData; deploying file content as-is." -Level Warning
            }
        }
    }
    catch {
        Write-iSOCLog "Workbook '$folderName' could not be parsed for ARM detection ($($_.Exception.Message)); deploying file content as-is." -Level Warning
    }

    [pscustomobject]@{
        PSTypeName   = 'iSOCDeployments.Request'
        ContentType  = $Item.ContentType
        Identity     = ([string]$workbookId).ToLowerInvariant()
        ResourceName = [string]$workbookId
        Body         = @{
            location   = $Context.Region
            kind       = 'shared'
            properties = @{
                displayName    = $displayName
                serializedData = $serializedData
                version        = '1.0'
                category       = $category
                sourceId       = $Context.WorkspaceResourceId
            }
        }
    }
}

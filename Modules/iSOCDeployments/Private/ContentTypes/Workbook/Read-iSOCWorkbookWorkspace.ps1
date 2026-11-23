#Requires -Version 7.6

<#
.SYNOPSIS
    ReadWorkspace handler for workbooks: the Sentinel workbooks saved against
    the workspace, with their content.

.DESCRIPTION
    Replaces the list and detail reads of Tools/Export-SentinelWorkbooks.ps1,
    which read only the first page of the list (MIGRATION.md edit E25).

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/Workbook/Read-iSOCWorkbookWorkspace.ps1
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

function Read-iSOCWorkbookWorkspace {
    <#
    .SYNOPSIS
        List the workspace's Sentinel workbooks, every page, each with its
        serializedData.

    .DESCRIPTION
        Lists the workbooks in the workspace's resource group in the
        sentinel category whose source is the workspace, asking for their
        content (canFetchContent), as the script did. A workbook the list
        returns without its serializedData is read on its own. One that
        cannot be read is returned as the list gave it, with the error in a
        ReadError property, so the export can say why it failed.

    .PARAMETER Context
        The workspace context.

    .PARAMETER ContentType
        The workbook content type.

    .OUTPUTS
        [psobject] The workbooks as the API returns them.

    .EXAMPLE
        $workbooks = @(Read-iSOCWorkbookWorkspace -Context $ctx -ContentType $type)
    #>
    [CmdletBinding()]
    [OutputType([psobject])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Context,

        [Parameter(Mandatory)]
        [psobject] $ContentType
    )

    $apiVersion = Get-iSOCApiVersion $ContentType.ApiVersion
    $path = (Get-iSOCResourcePath -Context $Context -ContentType $ContentType) +
    '?category=sentinel&sourceId=' + [Uri]::EscapeDataString($Context.WorkspaceResourceId) + '&canFetchContent=true'
    Write-iSOCLog 'Listing workbooks...'
    $workbooks = @(Invoke-iSOCRestRequest -Method GET -Path $path -ApiVersion $apiVersion -Context $Context | Where-Object { $null -ne $_ })
    Write-iSOCLog "Found $($workbooks.Count) workbook(s) in the workspace."

    foreach ($workbook in $workbooks) {
        if (Get-iSOCPropertyValue -InputObject $workbook -Path 'properties.serializedData') {
            $workbook
            continue
        }
        $displayName = Get-iSOCPropertyValue -InputObject $workbook -Path 'properties.displayName'
        Write-iSOCLog "  '$displayName' had no content in the list response; fetching detail..."
        try {
            $detail = Invoke-iSOCRestRequest -Method GET -Path "$(Get-iSOCPropertyValue -InputObject $workbook -Path 'id')?canFetchContent=true" -ApiVersion $apiVersion -Context $Context
            if ($null -ne $detail) { $detail } else { $workbook }
        } catch {
            $workbook | Add-Member -NotePropertyName ReadError -NotePropertyValue "detail fetch failed: $($_.Exception.Message)" -Force
            $workbook
        }
    }
}

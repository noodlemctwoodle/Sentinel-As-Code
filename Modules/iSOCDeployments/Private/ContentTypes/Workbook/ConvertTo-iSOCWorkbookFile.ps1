#Requires -Version 7.2

<#
.SYNOPSIS
    ToRepoFile handler for workbooks: the files a workspace workbook is
    written to.

.DESCRIPTION
    Copied from the export loop of Tools/Export-SentinelWorkbooks.ps1 and its
    Format-WorkbookJson and Write-WorkbookFolder.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/Workbook/ConvertTo-iSOCWorkbookFile.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.0
    Last Updated: 2026-11-03
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function ConvertTo-iSOCWorkbookFile {
    <#
    .SYNOPSIS
        Return workbook.json and metadata.json for a workspace workbook.

    .DESCRIPTION
        workbook.json is the gallery template, pretty-printed, with the
        workspace's resource id replaced by the repository's placeholder.
        metadata.json is Merge-iSOCWorkbookMetadata's merge of the
        workspace's display name (its ' - <workspace>' suffix removed),
        description and category with the folder's metadata.json, its
        sourceId the folder name and its workbookId the workbook's GUID.
        Both are JSON to depth 100, with LF line endings and one final
        newline; the script wrote to depth 32, so a deeper workbook lost
        its innermost levels (MIGRATION.md edit E26).

    .PARAMETER WorkspaceItem
        A workbook as Read-iSOCWorkbookWorkspace returns it, with its
        content.

    .PARAMETER Context
        The workspace context.

    .PARAMETER RelativePath
        The folder the workbook is written to; its name is the sourceId.

    .PARAMETER Existing
        The folder's files in the repository now, from
        Read-iSOCRepoItemFile, or nothing.

    .OUTPUTS
        [System.Collections.Specialized.OrderedDictionary] The text of
        workbook.json and metadata.json, by file name.

    .EXAMPLE
        $files = ConvertTo-iSOCWorkbookFile -WorkspaceItem $workbook -Context $ctx -RelativePath 'Content/Workbooks/Cost' -Existing $existing
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [psobject] $WorkspaceItem,

        [Parameter(Mandatory)]
        [psobject] $Context,

        [Parameter(Mandatory)]
        [string] $RelativePath,

        [AllowNull()]
        [object] $Existing
    )

    $rawName = [string](Get-iSOCPropertyValue -InputObject $WorkspaceItem -Path 'properties.displayName')
    $displayName = Get-iSOCWorkbookDisplayName -DisplayName $rawName -WorkspaceName $Context.WorkspaceName
    if ($displayName -ne $rawName) { Write-iSOCLog "  Stripped workspace suffix: '$rawName' -> '$displayName'" }
    $folderName = ($RelativePath -split '/')[-1]

    $content = [string](Get-iSOCPropertyValue -InputObject $WorkspaceItem -Path 'properties.serializedData') | ConvertFrom-Json -Depth 100
    $pretty = $content | ConvertTo-Json -Depth 100
    $workbookJson = ConvertTo-iSOCPortableWorkbookJson -Json $pretty -WorkspaceResourceId $Context.WorkspaceResourceId
    if ($workbookJson -ne $pretty) { Write-iSOCLog '  Replaced workspace ARM ID with placeholder in workbook content.' }

    $existingMetadata = $null
    if ($null -ne $Existing -and $Existing.Contains('metadata.json')) {
        try { $existingMetadata = $Existing['metadata.json'] | ConvertFrom-Json -Depth 100 -ErrorAction Stop }
        catch { Write-iSOCLog "  The existing metadata.json in '$RelativePath' does not parse; treating it as absent." -Level Warning }
    }
    $id = [string](Get-iSOCPropertyValue -InputObject $WorkspaceItem -Path 'id')
    $metadata = Merge-iSOCWorkbookMetadata `
        -ApiDisplayName $displayName `
        -ApiDescription ([string](Get-iSOCPropertyValue -InputObject $WorkspaceItem -Path 'properties.description')) `
        -ApiCategory ([string](Get-iSOCPropertyValue -InputObject $WorkspaceItem -Path 'properties.category')) `
        -FolderName $folderName `
        -WorkbookId $(if ($id) { ($id -split '/')[-1] } else { '' }) `
        -ExistingMetadata $existingMetadata

    $lf = { param([string] $Text) $Text.Replace("`r`n", "`n") + "`n" }
    [ordered]@{
        'workbook.json' = & $lf $workbookJson
        'metadata.json' = & $lf (ConvertTo-Json -InputObject $metadata -Depth 100)
    }
}

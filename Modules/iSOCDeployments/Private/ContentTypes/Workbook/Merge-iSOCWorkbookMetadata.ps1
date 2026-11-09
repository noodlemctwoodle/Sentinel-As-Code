#Requires -Version 7.6

<#
.SYNOPSIS
    A workbook's metadata.json, merging the workspace's values with the
    folder's curated ones.

.DESCRIPTION
    Copied from Merge-WorkbookMetadata (Tools/Export-SentinelWorkbooks.ps1).
    The keys come out in the order written here; the script passed them
    through a [hashtable] parameter, which lost the order (MIGRATION.md edit
    E26).

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/Workbook/Merge-iSOCWorkbookMetadata.ps1
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

function Merge-iSOCWorkbookMetadata {
    <#
    .SYNOPSIS
        Return the metadata.json content for one workbook.

    .DESCRIPTION
        - displayName: the workspace's, unless the folder's differs from it
          only in case (a curated capitalisation);
        - description: the workspace's, unless it is empty and the folder's
          is not;
        - category: the folder's when it sets one ('sentinel', the
          workspace's default, says little), else the workspace's, else
          'sentinel';
        - sourceId: the folder name;
        - workbookId: the workbook's GUID, so a redeploy updates the same
          workbook;
        - and every other key the folder's metadata.json has, as it is.

    .PARAMETER ApiDisplayName
        The display name, its workspace suffix removed.

    .PARAMETER ApiDescription
        The workspace's description, possibly empty.

    .PARAMETER ApiCategory
        The workspace's category, possibly empty.

    .PARAMETER FolderName
        The folder the workbook is written to.

    .PARAMETER WorkbookId
        The workbook's GUID.

    .PARAMETER ExistingMetadata
        The folder's metadata.json parsed, or nothing.

    .OUTPUTS
        [System.Collections.Specialized.OrderedDictionary] displayName,
        description, category, sourceId, workbookId, then the others.

    .EXAMPLE
        Merge-iSOCWorkbookMetadata -ApiDisplayName 'Cost' -ApiDescription '' -ApiCategory 'sentinel' -FolderName 'Cost' -WorkbookId $id -ExistingMetadata $old
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Metadata is the name of the file it builds, metadata.json.')]
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $ApiDisplayName,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $ApiDescription,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $ApiCategory,

        [Parameter(Mandatory)]
        [string] $FolderName,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $WorkbookId,

        [AllowNull()]
        [object] $ExistingMetadata
    )

    $existing = @(Get-iSOCPropertyEntry -InputObject $ExistingMetadata)
    $old = @{}
    foreach ($entry in $existing) { $old[$entry.Name] = $entry.Value }
    $text = { param([string] $Name) if ($old.ContainsKey($Name) -and $null -ne $old[$Name]) { [string]$old[$Name] } else { '' } }

    $displayName = $ApiDisplayName
    $oldName = & $text 'displayName'
    if ($oldName -and $oldName -ieq $ApiDisplayName -and $oldName -cne $ApiDisplayName) { $displayName = $oldName }

    $description = $ApiDescription
    if ([string]::IsNullOrWhiteSpace($description)) {
        $oldDescription = & $text 'description'
        if (-not [string]::IsNullOrWhiteSpace($oldDescription)) { $description = $oldDescription }
    }

    $category = if ([string]::IsNullOrWhiteSpace($ApiCategory)) { 'sentinel' } else { $ApiCategory }
    $oldCategory = & $text 'category'
    if (-not [string]::IsNullOrWhiteSpace($oldCategory)) { $category = $oldCategory }

    $metadata = [ordered]@{
        displayName = $displayName
        description = $description
        category    = $category
        sourceId    = $FolderName
        workbookId  = $WorkbookId
    }
    foreach ($entry in $existing) {
        if (-not $metadata.Contains($entry.Name)) { $metadata[$entry.Name] = $entry.Value }
    }
    $metadata
}

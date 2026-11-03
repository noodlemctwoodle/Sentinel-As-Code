#Requires -Version 7.2

<#
.SYNOPSIS
    ReadRepo handler for workbooks.

.DESCRIPTION
    Replaces the folder walk and metadata read in Deploy-CustomWorkbooks
    (Deploy/content/Deploy-CustomContent.ps1).

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/Workbook/Read-iSOCWorkbookRepo.ps1
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

function Read-iSOCWorkbookRepo {
    <#
    .SYNOPSIS
        Read every workbook folder in the repository.

    .DESCRIPTION
        One item per folder directly under Content/Workbooks/, in repository
        order. Data is the parsed metadata.json, or nothing when the folder
        has none; a metadata.json that does not parse sets ParseError. The
        template itself is read when the request is built. Only workbook.json
        is recorded in the deployment state, as the script recorded it.

    .PARAMETER RepoPath
        The repository root.

    .PARAMETER ContentType
        The workbook content type.

    .OUTPUTS
        [pscustomobject] iSOCDeployments.RepoItem with FolderName,
        WorkbookPath, MetadataPath and Files.

    .EXAMPLE
        Read-iSOCWorkbookRepo -RepoPath $repo -ContentType $workbooks
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $RepoPath,

        [Parameter(Mandatory)]
        [psobject] $ContentType
    )

    foreach ($folder in Get-iSOCContentFile -RepoPath $RepoPath -ContentType $ContentType) {
        $workbookPath = Join-Path $folder.FullName 'workbook.json'
        $metadataPath = Join-Path $folder.FullName 'metadata.json'
        $data = $null
        $parseError = $null
        if (Test-Path -LiteralPath $metadataPath -PathType Leaf) {
            try { $data = Get-Content -LiteralPath $metadataPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop }
            catch { $parseError = "metadata.json does not parse: $($_.Exception.Message)" }
        }

        $workbookId = [string](Get-iSOCPropertyValue -InputObject $data -Path 'workbookId')
        $displayName = [string](Get-iSOCPropertyValue -InputObject $data -Path 'displayName')

        [pscustomobject]@{
            PSTypeName   = 'iSOCDeployments.RepoItem'
            ContentType  = $ContentType.Name
            Identity     = if ($workbookId) { $workbookId.ToLowerInvariant() } else { $null }
            Name         = if ($displayName) { $displayName } else { $folder.Name -creplace '([a-z])([A-Z])', '$1 $2' }
            Path         = $folder.FullName
            RelativePath = ConvertTo-iSOCRepoRelativePath -Path $folder.FullName -RepoPath $RepoPath
            Source       = 'Custom'
            Data         = $data
            ParseError   = $parseError
            FolderName   = $folder.Name
            WorkbookPath = $workbookPath
            MetadataPath = $metadataPath
            Files        = @($workbookPath)
        }
    }
}

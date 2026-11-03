#Requires -Version 7.2

<#
.SYNOPSIS
    Classify handler for workbooks: where a workspace workbook's source of
    truth is.

.DESCRIPTION
    Replaces the Content Hub and content checks in the export loop of
    Tools/Export-SentinelWorkbooks.ps1. The script knew a workbook was in the
    repository only by the folder its display name made; here it is known by
    its GUID, wherever its folder is (MIGRATION.md edit E25).

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/Workbook/Get-iSOCWorkbookSource.ps1
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

function Get-iSOCWorkbookSource {
    <#
    .SYNOPSIS
        Say whether a workspace workbook is governed by a repository folder,
        came from Content Hub, or exists only in the workspace.

    .DESCRIPTION
        In order:
        - a workbook whose name (its GUID) is a repository workbook's
          workbookId, or the GUID deploy makes for a folder with none, is
          governed by that folder (Custom); when two folders deploy it, it
          is skipped as ambiguous;
        - one a Content Hub solution installed is from Content Hub, and
          skipped when Content Hub is excluded;
        - anything else exists only in the workspace (Orphan).
        Then a workbook that could not be read fails, and one with no
        content, or content that is not JSON, is skipped: there is nothing
        to write. The repository's workbooks and the Content Hub records
        are read once per run.

    .PARAMETER Run
        The run, for its options and its cache.

    .PARAMETER ContentType
        The workbook content type.

    .PARAMETER WorkspaceItem
        A workbook as Read-iSOCWorkbookWorkspace returns it.

    .OUTPUTS
        [hashtable] Source (Custom, ContentHub or Orphan), State (Skipped
        or Failed when there is nothing more to do; nothing otherwise),
        Reason, Expected (nothing: workbooks are not compared yet),
        SourceRef (the repository folder), SourcePath and Solution.

    .EXAMPLE
        $source = Get-iSOCWorkbookSource -Run $run -ContentType $workbooks -WorkspaceItem $workbook
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Run,

        [Parameter(Mandatory)]
        [psobject] $ContentType,

        [Parameter(Mandatory)]
        [psobject] $WorkspaceItem
    )

    $cache = $Run.Cache
    $key = $ContentType.Name
    if (-not $cache.ContainsKey("$key.Repo")) {
        $byId = @{}
        foreach ($item in @(Invoke-iSOCContentTypeHandler -ContentType $ContentType -Handler ReadRepo -Parameters @{ RepoPath = $Run.RepoPath; ContentType = $ContentType })) {
            $id = if ($item.Identity) { $item.Identity } else { Get-iSOCWorkbookResourceName -Context $Run.Context -FolderName $item.FolderName }
            if (-not $byId.ContainsKey($id)) { $byId[$id] = [System.Collections.Generic.List[object]]::new() }
            $byId[$id].Add($item)
        }
        $cache["$key.Repo"] = $byId
        $cache["$key.ContentHub"] = Get-iSOCContentHubWorkbookLookup -Context $Run.Context
    }

    $result = @{ Source = $null; State = $null; Reason = ''; Expected = $null; SourceRef = $null; SourcePath = $null; Solution = $null }
    $name = ([string](Get-iSOCPropertyValue -InputObject $WorkspaceItem -Path 'name')).ToLowerInvariant()
    $repo = $cache["$key.Repo"]
    if ($name -and $repo.ContainsKey($name)) {
        $found = $repo[$name]
        $result.Source = 'Custom'
        if ($found.Count -gt 1) {
            $result.State = 'Skipped'
            $result.Reason = "ambiguous: $(($found | ForEach-Object { $_.RelativePath }) -join ' and ') all deploy it"
            return $result
        }
        $result.SourceRef = $found[0].RelativePath
        $result.SourcePath = $found[0].Path
    }
    else {
        $id = [string](Get-iSOCPropertyValue -InputObject $WorkspaceItem -Path 'id')
        $hub = $cache["$key.ContentHub"]
        if ($id -and $hub.ContainsKey($id)) {
            $result.Source = 'ContentHub'
            $result.Solution = $hub[$id]
            if (@($Run.Options.ExcludeSource) -contains 'ContentHub') {
                $result.State = 'Skipped'
                $result.Reason = 'a Content Hub workbook, which belongs to its solution (-IncludeContentHub exports it)'
                return $result
            }
        }
        else {
            $result.Source = 'Orphan'
        }
    }

    $readError = $WorkspaceItem.PSObject.Properties['ReadError']
    if ($readError) {
        $result.State = 'Failed'
        $result.Reason = [string]$readError.Value
        return $result
    }
    $serialised = [string](Get-iSOCPropertyValue -InputObject $WorkspaceItem -Path 'properties.serializedData')
    if (-not $serialised) {
        $result.State = 'Skipped'
        $result.Reason = 'no serializedData, even read on its own (a Content Hub gallery template not customised in this workspace, typically)'
        return $result
    }
    try { $null = $serialised | ConvertFrom-Json -Depth 100 -ErrorAction Stop }
    catch {
        $result.State = 'Skipped'
        $result.Reason = "its serializedData does not parse as JSON: $($_.Exception.Message)"
    }
    $result
}

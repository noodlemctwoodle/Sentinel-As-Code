#Requires -Version 7.2

<#
.SYNOPSIS
    Classify handler for playbooks: whether the repository already has a
    Logic App.

.DESCRIPTION
    The script (847ef86:Tools/Export-Playbooks.ps1) knew a playbook was in the repository only by the
    file its name and trigger made; here it is known by its PlaybookName,
    wherever its file is (MIGRATION.md edit E25).

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/Playbook/Get-iSOCPlaybookSource.ps1
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

function Get-iSOCPlaybookSource {
    <#
    .SYNOPSIS
        Say whether a Logic App is governed by a repository template or
        exists only in the workspace.

    .DESCRIPTION
        A Logic App whose name is a repository template's PlaybookName
        default is governed by that template (Custom); when two templates
        name it, it is skipped as ambiguous. Anything else exists only in
        the workspace (Orphan). Then a Logic App that could not be read
        fails, and one with no workflow definition is skipped. The
        repository's templates are read once per run.

    .PARAMETER Run
        The run, for its cache.

    .PARAMETER ContentType
        The playbook content type.

    .PARAMETER WorkspaceItem
        A Logic App as Read-iSOCPlaybookWorkspace returns it.

    .OUTPUTS
        [hashtable] Source (Custom or Orphan), State (Skipped or Failed
        when there is nothing more to do; nothing otherwise), Reason,
        Expected (nothing: playbooks are not compared yet), SourceRef (the
        repository template), SourcePath and Solution (nothing).

    .EXAMPLE
        $source = Get-iSOCPlaybookSource -Run $run -ContentType $playbooks -WorkspaceItem $app
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
            if (-not $item.Identity) { continue }
            if (-not $byId.ContainsKey($item.Identity)) { $byId[$item.Identity] = [System.Collections.Generic.List[object]]::new() }
            $byId[$item.Identity].Add($item)
        }
        $cache["$key.Repo"] = $byId
    }

    $result = @{ Source = 'Orphan'; State = $null; Reason = ''; Expected = $null; SourceRef = $null; SourcePath = $null; Solution = $null }
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

    $readError = $WorkspaceItem.PSObject.Properties['ReadError']
    if ($readError) {
        $result.State = 'Failed'
        $result.Reason = [string]$readError.Value
        return $result
    }
    if (-not (Get-iSOCPropertyValue -InputObject $WorkspaceItem -Path 'properties.definition')) {
        $result.State = 'Skipped'
        $result.Reason = 'no workflow definition returned'
    }
    $result
}

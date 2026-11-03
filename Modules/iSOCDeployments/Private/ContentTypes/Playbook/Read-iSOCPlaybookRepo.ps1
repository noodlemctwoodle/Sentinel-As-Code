#Requires -Version 7.2

<#
.SYNOPSIS
    ReadRepo handler for playbooks.

.DESCRIPTION
    Replaces the template search in Deploy-CustomPlaybooks
    (Deploy/content/Deploy-CustomContent.ps1).

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/Playbook/Read-iSOCPlaybookRepo.ps1
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

function Read-iSOCPlaybookRepo {
    <#
    .SYNOPSIS
        Read every playbook template in the repository.

    .DESCRIPTION
        One item per JSON file under Content/Playbooks/, leaving out
        parameter files (*.parameters.json) and anything in a folder named
        Template, as the script did. An item is named Category/File after
        its folder, or File alone in Content/Playbooks/ itself, and keeps
        the path of the parameters file deploy passes when there is one.
        Its identity is the template's PlaybookName default, else the file
        name, in lower case.

    .PARAMETER RepoPath
        The repository root.

    .PARAMETER ContentType
        The playbook content type.

    .OUTPUTS
        [pscustomobject] iSOCDeployments.RepoItem with Category, BaseName
        and ParametersPath.

    .EXAMPLE
        Read-iSOCPlaybookRepo -RepoPath $repo -ContentType $playbooks
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $RepoPath,

        [Parameter(Mandatory)]
        [psobject] $ContentType
    )

    $isTemplate = { param($File) $File.Name -notmatch '\.parameters\.json$' -and $File.Directory.Name -ne 'Template' }
    foreach ($item in Read-iSOCJsonRepoItem -RepoPath $RepoPath -ContentType $ContentType -Filter $isTemplate) {
        $file = Get-Item -LiteralPath $item.Path
        $category = $file.Directory.Name
        $playbookName = [string](Get-iSOCPropertyValue -InputObject $item.Data -Path 'parameters.PlaybookName.defaultValue')
        if (-not $playbookName) { $playbookName = $file.BaseName }

        $item.Identity = $playbookName.ToLowerInvariant()
        $item.Name = if ($category -eq 'Playbooks') { $file.BaseName } else { "$category/$($file.BaseName)" }
        $item | Add-Member -NotePropertyName Category -NotePropertyValue $category
        $item | Add-Member -NotePropertyName BaseName -NotePropertyValue $file.BaseName
        $item | Add-Member -NotePropertyName ParametersPath -NotePropertyValue (Join-Path $file.DirectoryName "$($file.BaseName).parameters.json")
        $item
    }
}

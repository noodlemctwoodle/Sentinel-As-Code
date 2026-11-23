#Requires -Version 7.6

<#
.SYNOPSIS
    ReadRepo handler for playbooks.

.DESCRIPTION
    Replaces the template search in Deploy-CustomPlaybooks
    (Deploy/content/Deploy-CustomContent.ps1), and reads Bicep playbooks
    too (MIGRATION.md E47).

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/Playbook/Read-iSOCPlaybookRepo.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.2.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Read-iSOCPlaybookRepo {
    <#
    .SYNOPSIS
        Read every playbook template in the repository.

    .DESCRIPTION
        One item per .bicep and .json file under Content/Playbooks/, in
        repository order, leaving out parameter files (*.parameters.json),
        bicepconfig.json and anything in a folder named Template, as the
        script did. The Bicep files are compiled together with the Bicep CLI
        (checked for first, so a repository of JSON playbooks never needs
        it), and each item's Data is its compiled template, so the rest of
        the type treats both formats alike; one that does not compile is
        returned with the compiler's errors as its ParseError. An item is
        named Category/File after its folder, or File alone in
        Content/Playbooks/ itself, and keeps the path of the parameters file
        deploy passes when there is one. Its identity is the template's
        PlaybookName default, else the file name, in lower case.

    .PARAMETER RepoPath
        The repository root.

    .PARAMETER ContentType
        The playbook content type.

    .OUTPUTS
        [pscustomobject] iSOCDeployments.RepoItem with Category, BaseName,
        ParametersPath and Format (Bicep or Json).

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

    $isTemplate = {
        param($File)
        $File.Name -notmatch '\.parameters\.json$' -and $File.Name -ne 'bicepconfig.json' -and $File.Directory.Name -ne 'Template'
    }
    $isJson = { param($File) $File.Extension -ieq '.json' -and (& $isTemplate $File) }

    $items = [System.Collections.Generic.List[object]]::new()
    foreach ($item in Read-iSOCJsonRepoItem -RepoPath $RepoPath -ContentType $ContentType -Filter $isJson) { $items.Add($item) }

    $bicepFiles = @(Get-iSOCContentFile -RepoPath $RepoPath -ContentType $ContentType | Where-Object { $_.Extension -ieq '.bicep' -and (& $isTemplate $_) })
    if ($bicepFiles.Count -gt 0) {
        Assert-iSOCPrerequisite -Name bicep -Purpose 'reading Bicep playbooks'
        $builds = @(Invoke-iSOCBicep -Path @($bicepFiles | ForEach-Object { $_.FullName }))
        for ($i = 0; $i -lt $bicepFiles.Count; $i++) {
            $relative = ConvertTo-iSOCRepoRelativePath -Path $bicepFiles[$i].FullName -RepoPath $RepoPath
            $build = $builds[$i]
            $items.Add([pscustomobject]@{
                    PSTypeName   = 'iSOCDeployments.RepoItem'
                    ContentType  = $ContentType.Name
                    Identity     = $null
                    Name         = $bicepFiles[$i].BaseName
                    Path         = $bicepFiles[$i].FullName
                    RelativePath = $relative
                    Source       = if ($relative -match '(^|/)Community/') { 'Community' } else { 'Custom' }
                    # Parsed as ConvertFrom-Json parses a JSON playbook, so Data
                    # has the same shape whichever format the file is in.
                    Data         = if ($build.Succeeded) { $build.Json | ConvertFrom-Json } else { $null }
                    ParseError   = if ($build.Succeeded) { $null } else { "the Bicep does not compile: $(@($build.Errors) -join ' ')" }
                })
        }
        $items.Sort([System.Comparison[object]] { param($a, $b) [string]::CompareOrdinal($a.RelativePath, $b.RelativePath) })
    }

    foreach ($item in $items) {
        $file = Get-Item -LiteralPath $item.Path
        $category = $file.Directory.Name
        $playbookName = [string](Get-iSOCPropertyValue -InputObject $item.Data -Path 'parameters.PlaybookName.defaultValue')
        if (-not $playbookName) { $playbookName = $file.BaseName }

        $item.Identity = $playbookName.ToLowerInvariant()
        $item.Name = if ($category -eq 'Playbooks') { $file.BaseName } else { "$category/$($file.BaseName)" }
        $item | Add-Member -NotePropertyName Category -NotePropertyValue $category
        $item | Add-Member -NotePropertyName BaseName -NotePropertyValue $file.BaseName
        $item | Add-Member -NotePropertyName ParametersPath -NotePropertyValue (Join-Path $file.DirectoryName "$($file.BaseName).parameters.json")
        $item | Add-Member -NotePropertyName Format -NotePropertyValue $(if ($file.Extension -ieq '.bicep') { 'Bicep' } else { 'Json' })
        $item
    }
}

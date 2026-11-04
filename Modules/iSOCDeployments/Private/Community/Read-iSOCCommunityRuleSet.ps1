#Requires -Version 7.2

<#
.SYNOPSIS
    Every rule a community source's checkout holds.

.DESCRIPTION
    Replaces the collection loops of Invoke-Main (Tools/Import-CommunityRules.ps1). Each folder's files
    are read in ordinal order of name, so every platform builds the same
    README and manifest (MIGRATION.md edit E28).

.NOTES
    File:         Modules/iSOCDeployments/Private/Community/Read-iSOCCommunityRuleSet.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.0
    Last Updated: 2026-11-04
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Read-iSOCCommunityRuleSet {
    <#
    .SYNOPSIS
        Read and normalise the rules of a checkout, and say which were left
        out.

    .DESCRIPTION
        The *.yaml files directly in each of the source's YAML folders,
        then, with -IncludeKqlConversion, the alertRules resources of every
        azuredeploy.json under its ARM folders. A folder the checkout does
        not have is warned about and passed over.

    .PARAMETER Path
        The checkout.

    .PARAMETER Source
        The community source.

    .PARAMETER SourceRepo
        The repository cloned, for the ids an ARM rule without a template
        name is given.

    .PARAMETER IncludeKqlConversion
        Read the ARM folders too.

    .OUTPUTS
        [pscustomobject] Pending (RelativePath, YamlContent, Category and
        SourceFile for each rule) and Skipped (Category, Name, SourceFile
        and Reason for each one left out).

    .EXAMPLE
        $set = Read-iSOCCommunityRuleSet -Path $checkout.Path -Source $source -SourceRepo $repo
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [hashtable] $Source,

        [Parameter(Mandatory)]
        [string] $SourceRepo,

        [switch] $IncludeKqlConversion
    )

    $pending = [System.Collections.Generic.List[object]]::new()
    $skipped = [System.Collections.Generic.List[object]]::new()

    Write-iSOCLog 'Collecting rules' -Level Section
    foreach ($folder in $Source.YamlFolders.Keys) {
        $category = $Source.YamlFolders[$folder]
        $folderPath = Join-Path $Path $folder
        if (-not (Test-Path -LiteralPath $folderPath)) {
            Write-iSOCLog "Source folder not found, skipping: $folder" -Level Warning
            continue
        }
        $files = [string[]]@(Get-ChildItem -LiteralPath $folderPath -Filter '*.yaml' -File -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
        [Array]::Sort($files, [System.StringComparer]::Ordinal)
        foreach ($name in $files) {
            $file = Join-Path $folderPath $name
            $rule = Read-iSOCCommunityYamlRule -Path $file -Source $Source
            if ($rule.Error) {
                $skipped.Add([pscustomobject]@{ Category = $category; Name = $name; SourceFile = $file; Reason = $rule.Error })
                continue
            }
            $pending.Add(@{ RelativePath = "$category/$name"; YamlContent = $rule.YamlContent; Category = $category; SourceFile = $file })
        }
    }

    if ($IncludeKqlConversion) {
        Write-iSOCLog 'Processing ARM/KQL folders' -Level Section
        foreach ($folder in $Source.ArmFolders.Keys) {
            $category = $Source.ArmFolders[$folder]
            $folderPath = Join-Path $Path $folder
            if (-not (Test-Path -LiteralPath $folderPath)) {
                Write-iSOCLog "ARM source folder not found, skipping: $folder" -Level Warning
                continue
            }
            foreach ($rule in @(Read-iSOCCommunityArmRule -FolderPath $folderPath -Category $category -Source $Source -SourceRepo $SourceRepo)) {
                if ($rule.Error) {
                    $skipped.Add([pscustomobject]@{ Category = $category; Name = $rule.Name; SourceFile = $rule.SourceFile; Reason = $rule.Error })
                    continue
                }
                $pending.Add(@{ RelativePath = "$category/$($rule.Name)"; YamlContent = $rule.YamlContent; Category = $category; SourceFile = $rule.SourceFile })
            }
        }
    }

    Write-iSOCLog "Total rules collected: $($pending.Count)"
    [pscustomobject]@{ Pending = $pending; Skipped = $skipped.ToArray() }
}

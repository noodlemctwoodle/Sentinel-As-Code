#Requires -Version 7.2

<#
.SYNOPSIS
    The community rules in a folder of ARM templates.

.DESCRIPTION
    Copied from Get-ArmRulesFromFolder (Tools/Import-CommunityRules.ps1).

.NOTES
    File:         Modules/iSOCDeployments/Private/Community/Read-iSOCCommunityArmRule.ps1
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

function Read-iSOCCommunityArmRule {
    <#
    .SYNOPSIS
        Return one rule per alertRules resource in every azuredeploy.json
        under a folder.

    .DESCRIPTION
        Each rule's file name is its display name with every run of other
        characters made one hyphen. A rule with no alertRuleTemplateName is
        given an id made from the source repository, the category and that
        file name, the same on every run. A template that does not parse,
        has no alertRules resource, or holds a rule that cannot be
        normalised is warned about; a rule that cannot be normalised comes
        back with an Error.

    .PARAMETER FolderPath
        The folder to search, at any depth.

    .PARAMETER Category
        The category the rules go to.

    .PARAMETER Source
        The community source.

    .PARAMETER SourceRepo
        The repository cloned, for the ids it makes.

    .OUTPUTS
        [pscustomobject] Name (the file name), YamlContent, SourceFile and
        Error.

    .EXAMPLE
        Read-iSOCCommunityArmRule -FolderPath $folder -Category AzureActivity -Source $source -SourceRepo $repo
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $FolderPath,

        [Parameter(Mandatory)]
        [string] $Category,

        [Parameter(Mandatory)]
        [hashtable] $Source,

        [Parameter(Mandatory)]
        [string] $SourceRepo
    )

    $files = [string[]]@(Get-ChildItem -LiteralPath $FolderPath -Recurse -Filter 'azuredeploy.json' -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
    if ($files.Count -eq 0) {
        Write-iSOCLog "No azuredeploy.json found under '$FolderPath'" -Level Warning
        return
    }
    [Array]::Sort($files, [System.StringComparer]::Ordinal)
    $repository = ($SourceRepo.TrimEnd('/') -replace '\.git$', '').TrimEnd('/')

    foreach ($file in $files) {
        try { $template = Get-Content -LiteralPath $file -Raw -Encoding utf8 | ConvertFrom-Json -Depth 100 -ErrorAction Stop }
        catch {
            Write-iSOCLog "Failed to parse ARM template '$file': $($_.Exception.Message)" -Level Warning
            continue
        }
        $resources = Get-iSOCPropertyValue -InputObject $template -Path 'resources'
        $alertRules = @($resources | Where-Object { $null -ne $_ -and (Get-iSOCPropertyValue -InputObject $_ -Path 'type') -in @('Microsoft.SecurityInsights/alertRules', 'Microsoft.OperationalInsights/workspaces/providers/alertRules') })
        if ($alertRules.Count -eq 0) {
            Write-iSOCLog "No alertRule resources found in '$file'" -Level Warning
            continue
        }
        foreach ($resource in $alertRules) {
            $displayName = Get-iSOCPropertyValue -InputObject $resource -Path 'properties.displayName'
            if ($null -eq $displayName) { $displayName = 'UnknownRule' }
            $safeName = ((([string]$displayName) -replace '[^\w\-]', '-') -replace '-{2,}', '-').Trim('-')
            $name = "$safeName.yaml"
            try {
                $fallback = New-iSOCCommunityRuleId -Name "$repository#arm#$Category/$name"
                $yaml = ConvertFrom-iSOCArmAlertRule -Resource $resource -SourceFile $file -Source $Source -FallbackId $fallback
                [pscustomobject]@{ Name = $name; YamlContent = $yaml; SourceFile = $file; Error = $null }
            }
            catch {
                Write-iSOCLog "Skipping ARM rule in '$file': $($_.Exception.Message)" -Level Warning
                [pscustomobject]@{ Name = $name; YamlContent = $null; SourceFile = $file; Error = $_.Exception.Message }
            }
        }
    }
}

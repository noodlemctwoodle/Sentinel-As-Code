#Requires -Version 7.6

<#
.SYNOPSIS
    ReadRepo handler for Defender XDR custom detections.

.DESCRIPTION
    Replaces the reader in Deploy-DefenderDetections
    (Deploy/content/Deploy-DefenderDetections.ps1). A file written with the
    Graph fields retired on 2026-10-01 is translated to the current shape
    here, once, so validation, the request and a later compare all see the
    same rule.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/DefenderDetection/Read-iSOCDefenderDetectionRepo.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    Needs powershell-yaml when it runs. Import-iSOCYamlModule loads it
    then instead of #Requires, so the module imports without it.
#>

# Keeps the file help above from being read as the help of the function below.

function Read-iSOCDefenderDetectionRepo {
    <#
    .SYNOPSIS
        Read every Defender XDR custom detection file in the repository.

    .DESCRIPTION
        One item per file, in repository order, read by
        Read-iSOCYamlRepoItem and named by its displayName (the file name
        when it has none). Data is the file as written; Rule is the rule in
        the current Graph shape and LegacyFields the retired fields it was
        translated from. A file the deployer could not read fails, as it
        did: one that does not parse, one that holds no mapping, and one
        whose retired fields cannot be translated each carry ParseError.

    .PARAMETER RepoPath
        The repository root.

    .PARAMETER ContentType
        The Defender detection content type.

    .OUTPUTS
        [pscustomobject] iSOCDeployments.RepoItem, with Rule and
        LegacyFields.

    .EXAMPLE
        Read-iSOCDefenderDetectionRepo -RepoPath $repo -ContentType $detections
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $RepoPath,

        [Parameter(Mandatory)]
        [psobject] $ContentType
    )

    foreach ($item in Read-iSOCYamlRepoItem -RepoPath $RepoPath -ContentType $ContentType) {
        $rule = $null
        $legacyFields = @()
        if ($item.ParseError) {
            $item.ParseError = "YAML does not parse: $($item.ParseError)"
        } elseif ($item.Data -isnot [System.Collections.IDictionary]) {
            $item.ParseError = 'the file does not hold a YAML mapping'
        } else {
            $displayName = [string]$item.Data['displayName']
            if (-not [string]::IsNullOrWhiteSpace($displayName)) { $item.Name = $displayName }
            try {
                $translated = ConvertFrom-iSOCLegacyDefenderDetection -Rule $item.Data
                $rule = $translated.Rule
                $legacyFields = @($translated.LegacyFields)
            } catch {
                $item.ParseError = "the retired Graph fields cannot be translated: $($_.Exception.Message)"
            }
        }
        $item | Add-Member -NotePropertyName Rule -NotePropertyValue $rule
        $item | Add-Member -NotePropertyName LegacyFields -NotePropertyValue $legacyFields
        $item
    }
}

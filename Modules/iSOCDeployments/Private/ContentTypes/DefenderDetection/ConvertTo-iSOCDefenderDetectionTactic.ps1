#Requires -Version 7.6

<#
.SYNOPSIS
    Build alertTemplate.tactics from a retired category and
    mitreTechniques list.

.DESCRIPTION
    Copied from ConvertTo-DetectionTactic
    (Deploy/content/Deploy-DefenderDetections.ps1).

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/DefenderDetection/ConvertTo-iSOCDefenderDetectionTactic.ps1
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

function ConvertTo-iSOCDefenderDetectionTactic {
    <#
    .SYNOPSIS
        Return one tactic holding the techniques, sub-techniques under
        their parent.

    .DESCRIPTION
        Sub-techniques (T1110.003) are grouped under their parent technique
        (T1110), in the order the techniques first appear.

    .PARAMETER Category
        The retired alertTemplate.category: the tactic.

    .PARAMETER MitreTechniques
        The retired alertTemplate.mitreTechniques.

    .OUTPUTS
        [object[]] A list of one tactic.

    .EXAMPLE
        ConvertTo-iSOCDefenderDetectionTactic -Category CredentialAccess -MitreTechniques 'T1110.003'
    #>
    [CmdletBinding()]
    [OutputType([object[]], [array])]
    param(
        [Parameter(Mandatory)]
        [string] $Category,

        [AllowNull()]
        [object[]] $MitreTechniques
    )

    $techniques = [ordered]@{}
    foreach ($raw in @($MitreTechniques)) {
        if ([string]::IsNullOrWhiteSpace([string]$raw)) { continue }
        $id = ([string]$raw).Trim()
        $parent = ($id -split '\.')[0]
        if (-not $techniques.Contains($parent)) {
            $techniques[$parent] = [System.Collections.Generic.List[string]]::new()
        }
        if ($id -ne $parent -and -not $techniques[$parent].Contains($id)) {
            $techniques[$parent].Add($id)
        }
    }

    $tactic = [ordered]@{ tactic = $Category }
    if ($techniques.Count -gt 0) {
        $tactic['techniques'] = @($techniques.Keys | ForEach-Object {
                $entry = [ordered]@{ technique = $_ }
                if ($techniques[$_].Count -gt 0) { $entry['subTechniques'] = @($techniques[$_]) }
                $entry
            })
    }
    , @($tactic)
}

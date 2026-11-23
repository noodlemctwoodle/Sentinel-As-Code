#Requires -Version 7.6

<#
.SYNOPSIS
    The MITRE ATT&CK tactics each technique belongs to, for the Defender
    detection validator.

.DESCRIPTION
    Graph rejects a detection whose alertTemplate.tactics put a technique
    under a tactic it does not belong to. The map ships as
    Resources/DefenderDetection/mitre-attack-tactics.json, built from
    MITRE ATT&CK Enterprise 18.1: the last release whose tactics are the
    fourteen Graph accepts (19.0 split Defense Evasion into Stealth and
    Defense Impairment). The map is the module's own; nothing is shared
    with iSOCBlueprint.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/DefenderDetection/Get-iSOCDefenderDetectionAttackMap.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-06
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCDefenderDetectionAttackMap {
    <#
    .SYNOPSIS
        Read the technique to tactic map.

    .DESCRIPTION
        Read on each call rather than kept in module state. Technique and
        sub-technique ids are looked up without case. A missing file is a
        warning and no map, and the validator then checks only the id
        patterns.

    .PARAMETER Path
        The map file. Defaults to the module's own.

    .OUTPUTS
        [pscustomobject] AttackVersion, and Techniques: a case-insensitive
        dictionary of id to the tactics it belongs to. Nothing when the
        file is missing.

    .EXAMPLE
        (Get-iSOCDefenderDetectionAttackMap).Techniques['T1047']
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $Path = (Join-Path $script:iSOCDeploymentsRoot 'Resources/DefenderDetection/mitre-attack-tactics.json')
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-iSOCLog "MITRE ATT&CK map not found at $Path; techniques are not checked against their tactics" -Level Warning
        return $null
    }

    $raw = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
    $techniques = [System.Collections.Generic.Dictionary[string, string[]]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($id in $raw['techniques'].Keys) { $techniques[$id] = [string[]]@($raw['techniques'][$id]) }

    [pscustomobject]@{
        AttackVersion = [string]$raw['attackVersion']
        Techniques    = $techniques
    }
}

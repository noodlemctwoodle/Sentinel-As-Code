#Requires -Version 7.2

<#
.SYNOPSIS
    The tenant's custom detection rules, by display name, read once per
    deployment run.

.DESCRIPTION
    Copied from Get-ExistingDetectionRules and the rule map in
    Deploy-DefenderDetections (Deploy/content/Deploy-DefenderDetections.ps1),
    with the US Government warning from Connect-GraphEnvironment. The
    script read nothing under its -WhatIf switch; the rules are read under
    -WhatIf too, so a dry run says which rules it would update and which it
    would create (MIGRATION.md edit E18).

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/DefenderDetection/Get-iSOCDefenderDetectionRuleId.ps1
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

function Get-iSOCDefenderDetectionRuleId {
    <#
    .SYNOPSIS
        Return the id of every custom detection rule the tenant has, keyed
        by display name.

    .DESCRIPTION
        The first call in a run lists the rules (every page) and keeps the
        map in the run's cache; later calls return it. Names match in any
        case, and when two rules share a name the last one listed wins, as
        before. When the list cannot be read the map is empty, with a
        warning, so every rule is treated as new.

    .PARAMETER Run
        The deployment run.

    .PARAMETER ContentType
        The Defender detection content type.

    .OUTPUTS
        [hashtable] Display name to rule id.

    .EXAMPLE
        $existing = Get-iSOCDefenderDetectionRuleId -Run $run -ContentType $detections
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Run,

        [Parameter(Mandatory)]
        [psobject] $ContentType
    )

    $cacheKey = "$($ContentType.Name).RuleIds"
    if ($Run.Cache.ContainsKey($cacheKey)) { return $Run.Cache[$cacheKey] }

    if ($Run.Context.IsGov) {
        Write-iSOCLog 'Azure Government cloud: Microsoft does not offer the custom detection rules API in US Government clouds, so this step is expected to fail.' -Level Warning
    }
    Write-iSOCLog 'Fetching existing custom detection rules...'
    $rules = @()
    try {
        $rules = @(Invoke-iSOCRestRequest -Method GET -Api Graph -Context $Run.Context -Path (Get-iSOCResourcePath -Context $Run.Context -ContentType $ContentType) -ApiVersion (Get-iSOCApiVersion $ContentType.ApiVersion))
        Write-iSOCLog "Found $($rules.Count) existing custom detection rule(s)."
    }
    catch {
        Write-iSOCLog "Could not fetch existing rules: $($_.Exception.Message). All rules will be created as new." -Level Warning
        $rules = @()
    }

    $map = @{}
    foreach ($existing in $rules) {
        $name = Get-iSOCPropertyValue -InputObject $existing -Path 'displayName'
        if ($name) { $map[[string]$name] = [string](Get-iSOCPropertyValue -InputObject $existing -Path 'id') }
    }
    $Run.Cache[$cacheKey] = $map
    $map
}

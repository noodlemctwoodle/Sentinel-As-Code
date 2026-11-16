#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-DET-13: Installed solution deprecated or no longer in the catalogue

.DESCRIPTION
    Gap check for rule SAC-DET-13 (Resources/Data/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Detection/Test-DeprecatedContentHubSolutions.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-16
    Component:    iSOC Blueprint, Gap Engine
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# ------------------------------------------------------------
# SAC-DET-13, Installed solution deprecated or no longer in the catalogue
# ------------------------------------------------------------
function Test-DeprecatedContentHubSolutions {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    $installed = @($Inventory.ContentPackages | Where-Object { $null -ne $_ })
    $catalogue = @($Inventory.ContentProductPackages | Where-Object { $null -ne $_ })
    if ($installed.Count -eq 0 -or $catalogue.Count -eq 0) { return $null }
    $byId = @{}
    foreach ($p in $catalogue) {
        $id = [string](Get-PropOrDefault $p 'properties.contentId' '')
        if ($id) { $byId[$id] = $p }
    }
    $flagged = @(foreach ($p in $installed) {
        $id = [string](Get-PropOrDefault $p 'properties.contentId' '')
        if (-not $id) { continue }
        $name = [string](Get-PropOrDefault $p 'properties.displayName' $id)
        if (-not $byId.ContainsKey($id)) {
            [pscustomobject]@{ Solution = $name; ContentId = $id; Reason = 'not in catalogue' }
        } elseif (ConvertTo-GapBool (Get-PropOrDefault $byId[$id] 'properties.isDeprecated' $false)) {
            [pscustomobject]@{ Solution = $name; ContentId = $id; Reason = 'deprecated' }
        }
    })
    if ($flagged.Count -eq 0) { return $null }
    $sample = ($flagged | ForEach-Object { "$($_.Solution) ($($_.Reason))" }) -join '; '
    return New-Finding -Evidence "$(Format-BlueprintPlural $flagged.Count 'installed Content Hub solution') $(Select-GapWording $flagged.Count 'is' 'are') deprecated or no longer in the catalogue: $sample." -Detail @{ Count = $flagged.Count; Solutions = $flagged }
}

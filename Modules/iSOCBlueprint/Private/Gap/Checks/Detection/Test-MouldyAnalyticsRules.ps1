#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-DET-04: Mouldy rules, enabled, untouched > 12 months

.DESCRIPTION
    Gap check for rule SAC-DET-04 (Resources/Data/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Detection/Test-MouldyAnalyticsRules.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.2
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Gap Engine
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# ------------------------------------------------------------
# SAC-DET-04, Mouldy rules, enabled, untouched > 12 months
# ------------------------------------------------------------
function Test-MouldyAnalyticsRules {
    <#
    .SYNOPSIS
        Gap check SAC-DET-04: Mouldy rules, enabled, untouched > 12 months

    .PARAMETER Inventory
        The inventory Get-SentinelGap builds from the raw files.

    .OUTPUTS
        $null when the rule passes; otherwise the finding New-Finding returns, with its
        Evidence and Detail.
    #>
    [CmdletBinding()] param([Parameter(Mandatory = $true)]$Inventory)
    if (-not $Inventory.AlertRules) { return $null }
    $cutoff = (Get-Date).ToUniversalTime().AddDays(-365)
    # ConvertFrom-Json auto-deserialises ISO-8601 timestamps to [datetime];
    # round-tripping via [string] then TryParse uses the current culture and
    # can drop the round-trip on en-GB machines. Cast directly with a try
    # block so both [string] and [datetime] inputs work identically.
    $mouldy = @($Inventory.AlertRules | Where-Object {
            $kind = Get-PropOrDefault $_ 'kind' ''
            $enabled = Get-PropOrDefault $_ 'properties.enabled' $false
            $lm = Get-PropOrDefault $_ 'properties.lastModifiedUtc' $null
            $parsed = [datetime]::MinValue
            $tsValid = $false
            if ($lm) { try { $parsed = [datetime]$lm; $tsValid = $true } catch {} }
            ($kind -in @('Scheduled', 'NRT')) -and $enabled -and $tsValid -and ($parsed.ToUniversalTime() -lt $cutoff)
        })
    if ($mouldy.Count -eq 0) { return $null }
    $names = ($mouldy | ForEach-Object { Get-EvidenceName $_ 'properties.displayName', 'name' 'Unnamed rule' }) -join '; '
    return New-Finding -Evidence "$(Format-BlueprintPlural $mouldy.Count 'enabled Scheduled/NRT rule') not modified in over 12 months: $names." -Detail @{ Count = $mouldy.Count }
}

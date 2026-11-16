#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-DET-05: Rules disabled or in error

.DESCRIPTION
    Gap check for rule SAC-DET-05 (Resources/Data/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Detection/Test-RulesDisabledOrFailing.ps1
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
# SAC-DET-05, Rules disabled or in error
# ------------------------------------------------------------
function Test-RulesDisabledOrFailing {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    $bad = @($Inventory.AlertRules | Where-Object {
        $enabled = Get-PropOrDefault $_ 'properties.enabled' $true
        $kind = Get-PropOrDefault $_ 'kind' ''
        # Built-in / Microsoft-managed kinds whose enable-state we don't author.
        $managed = @('Fusion','MicrosoftSecurityIncidentCreation','MLBehaviorAnalytics','ThreatIntelligence')
        ($managed -notcontains $kind) -and (-not $enabled)
    })
    if ($bad.Count -gt 0) {
        $names = ($bad | ForEach-Object { Get-EvidenceName $_ 'properties.displayName', 'name' 'Unnamed rule' }) -join '; '
        # Many rules last modified on one day points at a bulk change rather
        # than individual tuning decisions; name the day when it covers at
        # least ten rules and a third of the disabled set.
        $byDay = @{}
        foreach ($r in $bad) {
            $lm = ConvertTo-GapIsoTime (Get-PropOrDefault $r 'properties.lastModifiedUtc' $null)
            if ($lm.Length -ge 10) { $d = $lm.Substring(0, 10); if (-not $byDay.ContainsKey($d)) { $byDay[$d] = 0 }; $byDay[$d]++ }
        }
        $bulkDay = $null; $bulkCount = 0
        foreach ($k in $byDay.Keys) { if ($byDay[$k] -gt $bulkCount) { $bulkCount = $byDay[$k]; $bulkDay = $k } }
        $bulk = ($bulkCount -ge 10 -and $bulkCount -ge [math]::Ceiling($bad.Count / 3.0))
        # A disabled rule that still produced alerts in the lookback was
        # switched off recently; those are the ones to ask about first.
        $firedById = @{}
        foreach ($f in @($Inventory.RulesFired)) {
            if ($null -eq $f) { continue }
            $rid = ([string](Get-PropOrDefault $f 'AlertRuleId' '')).Trim('{}').ToLowerInvariant()
            if ($rid) { $firedById[$rid] = ConvertTo-GapInt (Get-PropOrDefault $f 'Alerts' 0) }
        }
        $firedThenDisabled = @($bad | Where-Object { $firedById.ContainsKey(([string](Get-PropOrDefault $_ 'name' '')).ToLowerInvariant()) } | ForEach-Object {
            [pscustomobject]@{
                Rule         = Get-EvidenceName $_ 'properties.displayName', 'name' 'Unnamed rule'
                Alerts30d    = $firedById[([string](Get-PropOrDefault $_ 'name' '')).ToLowerInvariant()]
                LastModified = ConvertTo-GapIsoTime (Get-PropOrDefault $_ 'properties.lastModifiedUtc' $null)
            }
        } | Sort-Object { -$_.Alerts30d })
        $extra = ''
        if ($bulk) { $extra += " $(Format-BlueprintCount $bulkCount) of them were last modified on $(Format-BlueprintDate $bulkDay), which looks like a bulk change rather than rule-by-rule tuning." }
        if ($firedThenDisabled.Count -gt 0) {
            $win = (Get-GapWindow $Inventory).Days
            $sample = ($firedThenDisabled | ForEach-Object { "$($_.Rule) ($(Format-BlueprintPlural $_.Alerts30d 'alert') in $(Format-GapDays $win)$(if ($_.LastModified.Length -ge 10) { ', disabled ' + (Format-BlueprintDate $_.LastModified) }))" }) -join '; '
            $extra += " $(Format-BlueprintCount $firedThenDisabled.Count) of them produced alerts in the last $(Format-GapDays $win) and $(Select-GapWording $firedThenDisabled.Count 'was' 'were') disabled since: $sample."
        }
        return New-Finding -Evidence "$(Format-BlueprintPlural $bad.Count 'rule') disabled: $names.$extra" -Detail @{
            Count             = $bad.Count
            BulkDay           = $(if ($bulk) { $bulkDay } else { $null })
            BulkCount         = $(if ($bulk) { $bulkCount } else { 0 })
            FiredThenDisabled = $firedThenDisabled
        }
    }
    return $null
}

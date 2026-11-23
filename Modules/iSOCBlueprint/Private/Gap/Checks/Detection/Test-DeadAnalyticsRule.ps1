#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-DET-12: Enabled rule with zero alerts in the lookback

.DESCRIPTION
    Gap check for rule SAC-DET-12 (Resources/Data/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Detection/Test-DeadAnalyticsRule.ps1
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
# SAC-DET-12, Enabled rule with zero alerts in the lookback
# ------------------------------------------------------------
function Test-DeadAnalyticsRule {
    <#
    .SYNOPSIS
        Gap check SAC-DET-12: Enabled rule with zero alerts in the lookback

    .PARAMETER Inventory
        The inventory Get-SentinelGap builds from the raw files.

    .OUTPUTS
        $null when the rule passes; otherwise the finding New-Finding returns, with its
        Evidence and Detail.
    #>
    [CmdletBinding()] param([Parameter(Mandatory = $true)]$Inventory)
    $rules = @(Get-GapEnabledQueryRule $Inventory)
    if ($rules.Count -eq 0) { return $null }
    $volumes = @(Get-PropOrDefault $Inventory 'AnalyticsRuleVolumes' @() | Where-Object { $null -ne $_ })
    if (@(Get-PropOrDefault $Inventory 'RawFiles' @()) -contains 'rules-fired.json') {
        # The rules that fired, as the dashboard's alerts ring counts them: by
        # rule id, or by alert name for an alert that carries none. The alert
        # volumes also hold other products' alerts, whose names can match a
        # rule's title without the rule having fired.
        $firedIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $firedNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($f in @($Inventory.RulesFired)) {
            if ($null -eq $f) { continue }
            $id = ConvertTo-GapRuleKey (Get-PropOrDefault $f 'AlertRuleId' '')
            if ($id) { [void]$firedIds.Add($id); continue }
            $alertName = [string](Get-PropOrDefault $f 'AlertName' '')
            if ($alertName) { [void]$firedNames.Add($alertName) }
        }
        # Nothing fired and no alerts at all: a workspace not yet producing
        # alerts, not evidence that every rule is dead.
        if ($firedIds.Count -eq 0 -and $firedNames.Count -eq 0 -and $volumes.Count -eq 0) { return $null }
        $dead = @($rules | Where-Object {
                $id = ConvertTo-GapRuleKey (Get-PropOrDefault $_ 'name' '')
                $title = [string](Get-PropOrDefault $_ 'properties.displayName' '')
                -not (($id -and $firedIds.Contains($id)) -or ($title -and $firedNames.Contains($title)))
            })
    } else {
        # No rules-fired capture (an older run): the alert volumes are the
        # only signal, matched on the rule's display name.
        $named = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($v in $volumes) {
            $n = [string](Get-PropOrDefault $v 'AlertName' '')
            if ($n) { [void]$named.Add($n) }
        }
        if ($named.Count -eq 0) { return $null }    # no volumes -> no signal
        $dead = @($rules | Where-Object {
                $title = [string](Get-PropOrDefault $_ 'properties.displayName' '')
                $title -and -not $named.Contains($title)
            })
    }
    if ($dead.Count -eq 0) { return $null }
    $sample = ($dead | ForEach-Object { Get-EvidenceName $_ 'properties.displayName', 'name' 'Unnamed rule' }) -join '; '
    return New-Finding -Evidence "$(Format-BlueprintCount $dead.Count) of $(Format-BlueprintPlural $rules.Count 'enabled Scheduled/NRT rule') produced zero alerts in the last $(Format-GapDay (Get-GapWindow $Inventory).Days): $sample." -Detail @{ Count = $dead.Count; Enabled = $rules.Count }
}

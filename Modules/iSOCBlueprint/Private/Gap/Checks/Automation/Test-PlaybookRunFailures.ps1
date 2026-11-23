#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-AUT-02: Playbook runs failed in the last 7 days

.DESCRIPTION
    Gap check for rule SAC-AUT-02 (Resources/Data/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Automation/Test-PlaybookRunFailures.ps1
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
# SAC-AUT-02, Playbook runs failed in the last 7 days
# ------------------------------------------------------------
function Test-PlaybookRunFailures {
    <#
    .SYNOPSIS
        Gap check SAC-AUT-02: Playbook runs failed in the last 7 days

    .PARAMETER Inventory
        The inventory Get-SentinelGap builds from the raw files.

    .OUTPUTS
        $null when the rule passes; otherwise the finding New-Finding returns, with its
        Evidence and Detail.
    #>
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    if (@($Inventory.PlaybookRuns).Count -eq 0) { return $null }
    $failing = @($Inventory.PlaybookRuns | Where-Object {
        $null -ne $_ -and (ConvertTo-GapInt (Get-PropOrDefault $_ 'Failed7d' 0)) -gt 0
    } | Sort-Object { -(ConvertTo-GapInt (Get-PropOrDefault $_ 'Failed7d' 0)) })
    if ($failing.Count -eq 0) { return $null }
    $sample = ($failing | ForEach-Object {
        $last = ConvertTo-GapIsoTime (Get-PropOrDefault $_ 'LastFailureUtc' $null)
        $when = if ($last) { ", last $(Format-BlueprintDate $last -Time)" } else { '' }
        "$(Get-EvidenceName $_ 'Playbook' 'Unnamed playbook') ($(Format-BlueprintCount (ConvertTo-GapInt (Get-PropOrDefault $_ 'Failed7d' 0))) of $(Format-BlueprintPlural (ConvertTo-GapInt (Get-PropOrDefault $_ 'Runs7d' 0)) 'run') failed$when)"
    }) -join '; '
    return New-Finding -Evidence "$(Format-BlueprintPlural $failing.Count 'playbook') had failed runs in the last $(Format-GapDays (Get-GapWindow $Inventory).Days): $sample." -Detail @{
        Count     = $failing.Count
        Playbooks = @($failing | ForEach-Object {
            [pscustomobject]@{
                Playbook       = [string](Get-PropOrDefault $_ 'Playbook' '')
                Runs7d         = ConvertTo-GapInt (Get-PropOrDefault $_ 'Runs7d' 0)
                Failed7d       = ConvertTo-GapInt (Get-PropOrDefault $_ 'Failed7d' 0)
                LastFailureUtc = ConvertTo-GapIsoTime (Get-PropOrDefault $_ 'LastFailureUtc' $null)
            }
        })
    }
}

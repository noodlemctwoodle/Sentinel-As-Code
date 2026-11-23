#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-LOG-23: CEF records landing in the Syslog table

.DESCRIPTION
    Gap check for rule SAC-LOG-23 (Resources/Data/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Logging/Test-CefInSyslog.ps1
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
# SAC-LOG-23, CEF records landing in the Syslog table
# ------------------------------------------------------------
function Test-CefInSyslog {
    <#
    .SYNOPSIS
        Gap check SAC-LOG-23: CEF records landing in the Syslog table

    .PARAMETER Inventory
        The inventory Get-SentinelGap builds from the raw files.

    .OUTPUTS
        $null when the rule passes; otherwise the finding New-Finding returns, with its
        Evidence and Detail.
    #>
    [CmdletBinding()] param([Parameter(Mandatory = $true)]$Inventory)
    if ($Inventory.RawFiles -notcontains 'cef-in-syslog.json') { return $null }
    $rows = @($Inventory.CefInSyslog | Where-Object { $null -ne $_ -and [string](Get-PropOrDefault $_ 'Computer' '') })
    if ($rows.Count -eq 0) { return $null }
    $byHost = @($rows | Group-Object { [string]$_.Computer } | ForEach-Object {
            [pscustomobject]@{
                Computer = $_.Name
                Records  = (@($_.Group | ForEach-Object { ConvertTo-GapInt (Get-PropOrDefault $_ 'LogCount' 0) }) | Measure-Object -Sum).Sum
            }
        } | Sort-Object @{ Expression = 'Records'; Descending = $true }, Computer)
    $names = @($byHost | ForEach-Object { "$($_.Computer) ($(Format-BlueprintPlural $_.Records 'record'))" })
    return New-Finding -Evidence "CEF-formatted messages landed in Syslog instead of CommonSecurityLog in the last $(Format-GapDays (Get-GapWindow $Inventory).Days), from $(Format-BlueprintPlural $byHost.Count 'forwarder'): $($names -join ', ')." -Detail @{
        Forwarders = $byHost
    }
}

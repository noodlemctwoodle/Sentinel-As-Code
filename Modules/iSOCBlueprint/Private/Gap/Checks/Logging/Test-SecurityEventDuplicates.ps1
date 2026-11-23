#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-LOG-22: SecurityEvent records duplicated

.DESCRIPTION
    Gap check for rule SAC-LOG-22 (Resources/Data/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Logging/Test-SecurityEventDuplicates.ps1
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
# SAC-LOG-22, SecurityEvent records duplicated
# ------------------------------------------------------------
function Test-SecurityEventDuplicates {
    <#
    .SYNOPSIS
        Gap check SAC-LOG-22: SecurityEvent records duplicated

    .PARAMETER Inventory
        The inventory Get-SentinelGap builds from the raw files.

    .OUTPUTS
        $null when the rule passes; otherwise the finding New-Finding returns, with its
        Evidence and Detail.
    #>
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    if ($Inventory.RawFiles -notcontains 'security-event-duplicates.json') { return $null }
    $hosts = @($Inventory.SecurityEventDuplicates | Where-Object { $null -ne $_ -and [string](Get-PropOrDefault $_ 'Computer' '') })
    if ($hosts.Count -eq 0) { return $null }
    $names = @($hosts | ForEach-Object {
        $n = Get-PropOrDefault $_ 'DuplicateRecords' $null
        if ($null -ne $n) { "$([string]$_.Computer) ($(Format-BlueprintPlural (ConvertTo-GapInt $n) 'duplicated event'))" } else { [string]$_.Computer }
    })
    return New-Finding -Evidence "$(Format-BlueprintPlural $hosts.Count 'host') sent the same SecurityEvent record more than once in the last hour: $($names -join ', ')." -Detail @{ Hosts = @($hosts | ForEach-Object { [string]$_.Computer }) }
}

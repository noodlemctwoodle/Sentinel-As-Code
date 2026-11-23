#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-LOG-14: Data Lake mirroring candidate

.DESCRIPTION
    Gap check for rule SAC-LOG-14 (Resources/Data/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Logging/Test-DataLakeMirroringCandidate.ps1
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
# SAC-LOG-14, Data Lake mirroring candidate
# ------------------------------------------------------------
function Test-DataLakeMirroringCandidate {
    <#
    .SYNOPSIS
        Gap check SAC-LOG-14: Data Lake mirroring candidate

    .PARAMETER Inventory
        The inventory Get-SentinelGap builds from the raw files.

    .OUTPUTS
        $null when the rule passes; otherwise the finding New-Finding returns, with its
        Evidence and Detail.
    #>
    [CmdletBinding()] param([Parameter(Mandatory = $true)]$Inventory)
    # Heuristic, long-tail tables (>30 GB/30d, retention > 90d, plan = Analytics).
    $analyticsLongRetention = @($Inventory.WorkspaceTables | Where-Object {
            (Get-PropOrDefault $_ 'properties.plan' '') -eq 'Analytics' -and
            [int](Get-PropOrDefault $_ 'properties.totalRetentionInDays' 0) -gt 365
        })
    if ($analyticsLongRetention.Count -gt 0) {
        return New-Finding -Evidence "$(Format-BlueprintPlural $analyticsLongRetention.Count 'Analytics-plan table') with total retention of more than 365 days, $(Select-GapWording $analyticsLongRetention.Count 'a Data Lake mirroring candidate' 'Data Lake mirroring candidates')." -Detail @{ Count = $analyticsLongRetention.Count }
    }
    return $null
}

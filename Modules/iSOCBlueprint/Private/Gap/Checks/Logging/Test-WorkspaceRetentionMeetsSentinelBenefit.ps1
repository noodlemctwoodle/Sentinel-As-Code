#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-LOG-07: Workspace default retention < 90d

.DESCRIPTION
    Gap check for rule SAC-LOG-07 (Resources/Data/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Logging/Test-WorkspaceRetentionMeetsSentinelBenefit.ps1
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
# SAC-LOG-07, Workspace default retention < 90d
# ------------------------------------------------------------
function Test-WorkspaceRetentionMeetsSentinelBenefit {
    <#
    .SYNOPSIS
        Gap check SAC-LOG-07: Workspace default retention < 90d

    .PARAMETER Inventory
        The inventory Get-SentinelGap builds from the raw files.

    .OUTPUTS
        $null when the rule passes; otherwise the finding New-Finding returns, with its
        Evidence and Detail.
    #>
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    $retention = Get-PropOrDefault $Inventory.Workspace 'properties.retentionInDays' 0
    if ([int]$retention -lt 90) {
        return New-Finding -Evidence "Workspace default retention is $(Format-BlueprintPlural $retention 'day'); Sentinel includes the 30->90d upgrade at no extra cost on eligible tables." -Detail @{ RetentionInDays = [int]$retention }
    }
    return $null
}

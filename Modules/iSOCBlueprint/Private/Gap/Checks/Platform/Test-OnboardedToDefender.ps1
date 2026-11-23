#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-PLT-11: Sentinel still on Azure portal (info-only)

.DESCRIPTION
    Gap check for rule SAC-PLT-11 (Resources/Data/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Platform/Test-OnboardedToDefender.ps1
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
# SAC-PLT-11, Sentinel still on Azure portal (info-only)
# ------------------------------------------------------------
function Test-OnboardedToDefender {
    <#
    .SYNOPSIS
        Gap check SAC-PLT-11: Sentinel still on Azure portal (info-only)

    .PARAMETER Inventory
        The inventory Get-SentinelGap builds from the raw files.

    .OUTPUTS
        $null when the rule passes; otherwise the finding New-Finding returns, with its
        Evidence and Detail.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Inventory', Justification = 'Every gap check takes the inventory; this one raises an information finding that does not depend on it.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'The name is the published CheckName on every finding and is dispatched by name from best-practices.json.')]
    [CmdletBinding()] param([Parameter(Mandatory = $true)]$Inventory)
    # The defender-onboarding state is workspace-specific and exposed via a separate REST
    # surface that may not be in scope. Until we wire that detection, surface the deadline
    # universally as an Info finding so it appears in every report.
    return New-Finding -Evidence 'Sentinel in the Azure portal retires on 31 Mar 2027. Plan the migration to the unified Defender XDR experience.' -Detail @{ Deadline = '2027-03-31' }
}

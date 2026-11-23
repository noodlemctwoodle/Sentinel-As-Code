#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-COV-07: Recommended connectors not deployed

.DESCRIPTION
    Gap check for rule SAC-COV-07 (Resources/Data/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Coverage/Test-RecommendedConnectorsDeployed.ps1
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
# SAC-COV-07, Recommended connectors not deployed
# ------------------------------------------------------------
function Test-RecommendedConnectorsDeployed {
    <#
    .SYNOPSIS
        Gap check SAC-COV-07: Recommended connectors not deployed

    .PARAMETER Inventory
        The inventory Get-SentinelGap builds from the raw files.

    .OUTPUTS
        $null when the rule passes; otherwise the finding New-Finding returns, with its
        Evidence and Detail.
    #>
    [CmdletBinding()] param([Parameter(Mandatory = $true)]$Inventory)
    # $Inventory.DataConnectors can be $null when the workspace has no classic
    # connectors at all (some tenants run pure CCF). Coerce to an empty array
    # so Get-PropOrDefault doesn't see a $null Object.
    $connectors = @()
    if ($Inventory.DataConnectors) { $connectors = @($Inventory.DataConnectors) }
    $deployedKinds = @($connectors | ForEach-Object { Get-PropOrDefault $_ 'kind' '' }) | Sort-Object -Unique
    $recommended = @('AzureActiveDirectory', 'MicrosoftThreatProtection', 'AzureSecurityCenter', 'Office365', 'MicrosoftDefenderAdvancedThreatProtection', 'ThreatIntelligence')
    $missing = @($recommended | Where-Object { $deployedKinds -notcontains $_ })
    if ($missing.Count -gt 0) {
        return New-Finding -Evidence "Recommended $(Select-GapWording $missing.Count 'connector kind' 'connector kinds') not deployed: $($missing -join ', ')." -Detail @{ Missing = $missing }
    }
    return $null
}

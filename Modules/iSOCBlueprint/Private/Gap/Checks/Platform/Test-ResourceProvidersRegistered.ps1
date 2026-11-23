#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-PLT-09: Resource providers registered

.DESCRIPTION
    Gap check for rule SAC-PLT-09 (Resources/Data/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Platform/Test-ResourceProvidersRegistered.ps1
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
# SAC-PLT-09, Resource providers registered
# ------------------------------------------------------------
function Test-ResourceProvidersRegistered {
    <#
    .SYNOPSIS
        Gap check SAC-PLT-09: Resource providers registered

    .PARAMETER Inventory
        The inventory Get-SentinelGap builds from the raw files.

    .OUTPUTS
        $null when the rule passes; otherwise the finding New-Finding returns, with its
        Evidence and Detail.
    #>
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    $required = @('Microsoft.SecurityInsights','Microsoft.OperationalInsights','Microsoft.Insights')
    $bad = @($Inventory.ResourceProviders | Where-Object {
        $name = Get-PropOrDefault $_ 'ProviderNamespace' ''
        $state = Get-PropOrDefault $_ 'RegistrationState' ''
        ($required -contains $name) -and ($state -ne 'Registered')
    })
    if ($bad.Count -gt 0) {
        $names = ($bad | Select-Object -ExpandProperty ProviderNamespace) -join ', '
        return New-Finding -Evidence "$(Select-GapWording $bad.Count 'Resource provider' 'Resource providers') not registered: $names." -Detail @{ Providers = $names }
    }
    return $null
}

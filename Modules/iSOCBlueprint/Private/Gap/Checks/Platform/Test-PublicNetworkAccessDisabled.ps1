#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-PLT-06: Public network access enabled

.DESCRIPTION
    Gap check for rule SAC-PLT-06 (Resources/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Platform/Test-PublicNetworkAccessDisabled.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, Gap Engine
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# ------------------------------------------------------------
# SAC-PLT-06, Public network access enabled
# ------------------------------------------------------------
function Test-PublicNetworkAccessDisabled {
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    $ingest = Get-PropOrDefault $Inventory.Workspace 'properties.publicNetworkAccessForIngestion' 'Enabled'
    $query  = Get-PropOrDefault $Inventory.Workspace 'properties.publicNetworkAccessForQuery'     'Enabled'
    if ($ingest -eq 'Enabled' -or $query -eq 'Enabled') {
        return New-Finding -Evidence "Public network access enabled (Ingestion=$ingest, Query=$query)." -Detail @{ Ingestion = $ingest; Query = $query }
    }
    return $null
}

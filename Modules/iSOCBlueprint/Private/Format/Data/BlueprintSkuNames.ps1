#Requires -Version 7.6

<#
.SYNOPSIS
    Log Analytics workspace SKUs by the names the dashboard Overview uses.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Format/Data/BlueprintSkuNames.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.1.0
    Last Updated: 2026-11-16
    Component:    iSOC Blueprint, Blueprint text formatting
    Requires:     PowerShell 7.6+

    This file defines values rather than running.
#>

# Log Analytics workspace SKUs as the dashboard's Overview names them.
$script:BlueprintSkuName = @{
    PerGB2018 = 'Pay-as-you-go'; CapacityReservation = 'Commitment tier'; LACluster = 'Dedicated cluster'; Free = 'Free tier'
    Standalone = 'Standalone (legacy)'; PerNode = 'Per node (legacy)'; Premium = 'Premium (legacy)'; Standard = 'Standard (legacy)'
}

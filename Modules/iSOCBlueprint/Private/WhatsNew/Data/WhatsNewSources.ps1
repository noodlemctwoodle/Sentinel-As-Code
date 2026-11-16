#Requires -Version 7.6

<#
.SYNOPSIS
    The two What's new pages on Microsoft Learn that are read, with the product each covers.

.NOTES
    File:         Modules/iSOCBlueprint/Private/WhatsNew/Data/WhatsNewSources.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.1.0
    Last Updated: 2026-11-16
    Component:    iSOC Blueprint, What's new reading
    Requires:     PowerShell 7.6+

    This file defines values rather than running.
#>

$script:WhatsNewSources = @(
    [pscustomobject]@{ Product = 'Microsoft Sentinel'; Url = 'https://learn.microsoft.com/en-us/azure/sentinel/whats-new' }
    [pscustomobject]@{ Product = 'Microsoft Defender XDR'; Url = 'https://learn.microsoft.com/en-us/defender-xdr/whats-new' }
)

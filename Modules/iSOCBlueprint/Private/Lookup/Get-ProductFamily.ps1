#Requires -Version 7.6

<#
.SYNOPSIS
    Return the source family for the product that raised a first-party alert

.DESCRIPTION
    One of the helpers beside Get-TableFamily.ps1, which describes the whole.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Lookup/Get-ProductFamily.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-09
    Version:      0.1.0
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-ProductFamily {
    <#
    .SYNOPSIS
        Return the source family for the product that raised a first-party
        alert.

    .PARAMETER Product
        The ProductName as SecurityAlert records it, for example
        'Microsoft Defender for Endpoint'. Sentinel's own products are not
        mapped: the caller excludes them, because Sentinel rules read
        workspace tables and are counted through coverage instead.

    .OUTPUTS
        [string] One of 'Entra ID / Identity', 'Defender XDR',
        'Azure / Syslog' or 'Other'.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory = $false)] [AllowNull()] [AllowEmptyString()] [string] $Product)

    switch -regex ("$Product") {
        '^(Azure Active Directory Identity Protection|Microsoft Entra ID Protection|Azure Advanced Threat Protection|Microsoft Defender for Identity)$' { return 'Entra ID / Identity' }
        '^(Microsoft 365 Defender|Microsoft Defender XDR|Microsoft Defender Advanced Threat Protection|Microsoft Defender for Endpoint|Office 365 Advanced Threat Protection|Microsoft Defender for Office 365|Microsoft Cloud App Security|Microsoft Defender for Cloud Apps|Microsoft Data Loss Prevention|Microsoft Application Protection)$' { return 'Defender XDR' }
        '^(Azure Security Center|Microsoft Defender for Cloud|Azure Security Center for IoT|Microsoft Defender for IoT)$' { return 'Azure / Syslog' }
        default { return 'Other' }
    }
}

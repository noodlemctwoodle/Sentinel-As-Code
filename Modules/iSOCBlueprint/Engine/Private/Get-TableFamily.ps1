#Requires -Version 7.2

<#
.SYNOPSIS
    Map a Log Analytics table name to the telemetry source family it belongs
    to, for the Blueprint's ingest-flow and estate views.

.DESCRIPTION
    People who read the overview should not need to know what a table name
    means, so tables are grouped into families (Entra ID, Defender XDR,
    Azure and Syslog, Threat Intelligence, Custom logs). The Markdown
    renderer and the SharePoint site build both use this mapping, so the
    estate flow in the Markdown pack and the Sankey on the dashboard agree.
    Get-ProductFamily does the same for the products that raise first-party
    alerts (Defender XDR, Entra ID Protection, Defender for Identity,
    Defender for Cloud), so those alerts sit beside the family whose
    telemetry they belong to.

.NOTES
    File:         Modules/iSOCBlueprint/Engine/Private/Get-TableFamily.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-09
    Version:      0.2.1
    Last Updated: 2026-10-13
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.

    Credit and thanks: the source families behind the estate flow are
    based on the Sentinel health-check script by thinkndle, kindly given
    to the Sentinel-As-Code project. Thank you, thinkndle, for sharing
    your work so generously; it shaped much of the Blueprint's health,
    coverage and maturity reporting.
#>

function Get-TableFamily {
    <#
    .SYNOPSIS
        Return the source family for a table name.

    .PARAMETER Table
        A Log Analytics table name, for example 'SigninLogs'.

    .OUTPUTS
        [string] One of 'Threat Intelligence', 'Entra ID / Identity',
        'Defender XDR', 'Azure / Syslog', 'Custom logs' or 'Other'.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory = $false)] [AllowNull()] [AllowEmptyString()] [string] $Table)

    switch -regex ("$Table") {
        '^ThreatIntel'                                                   { return 'Threat Intelligence' }
        '^(AAD|Signin|SigninLogs|AuditLogs|MicrosoftGraphActivityLogs|MicrosoftServicePrincipalSignInLogs|AADNonInteractive|AADServicePrincipal|AADManagedIdentity|AADGraph)' { return 'Entra ID / Identity' }
        '^(Device|Alert|Email|CloudAppEvents|Identity|BehaviorAnalytics|UserPeerAnalytics|Anomalies)' { return 'Defender XDR' }
        '^(Syslog|CommonSecurityLog|AzureDiagnostics|AzureMetrics|AzureActivity)' { return 'Azure / Syslog' }
        '_CL$'                                                           { return 'Custom logs' }
        default                                                         { return 'Other' }
    }
}

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

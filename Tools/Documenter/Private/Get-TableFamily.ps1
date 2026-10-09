#Requires -Version 7.2

<#
.SYNOPSIS
    Map a Log Analytics table name to the telemetry source family it belongs
    to, for the Documenter's ingest-flow and estate views.

.DESCRIPTION
    People who read the overview should not need to know what a table name
    means, so tables are grouped into families (Entra ID, Defender XDR,
    Azure and Syslog, Threat Intelligence, Custom logs). The Markdown
    renderer and the SharePoint site build both use this mapping, so the
    estate flow in the Markdown pack and the Sankey on the dashboard agree.

.NOTES
    File:         Tools/Documenter/Private/Get-TableFamily.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-09
    Version:      0.1.0
    Last Updated: 2026-10-09
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
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

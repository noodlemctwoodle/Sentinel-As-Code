#Requires -Version 7.6

<#
.SYNOPSIS
    Name the Microsoft service a table's ingestion cost belongs to.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/CostEstimate/Get-BlueprintCostSource.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

# Sankey prep — computed outside the heredoc so $sankeyFlowText and
# $sankeyHeight can be interpolated, and the long-tail collapse logic
# is testable in isolation.
# ---------------------------------------------------------------------
function Get-BlueprintCostSource {
    param([string]$Table)
    switch -Regex ($Table) {
        '^ThreatIntel'                                             { return 'Microsoft Defender TI' }
        '^(SigninLogs|AuditLogs|AAD.*|MicrosoftGraphActivityLogs|MicrosoftServicePrincipalSignInLogs)$' { return 'Microsoft Entra ID' }
        '^(Device|Email|Url|Alert|Cloud|Identity).*'               { return 'Microsoft Defender XDR' }
        '^ASim'                                                    { return 'ASIM normaliser' }
        '^Office'                                                  { return 'Office 365' }
        '^(CommonSecurityLog|Syslog)$'                             { return 'CEF / Syslog' }
        '^(SecurityEvent|WindowsEvent|Event)$'                     { return 'Windows events' }
        '^(AzureActivity|AzureDiagnostics|AzureMetrics)$'          { return 'Azure platform' }
        '^Intune'                                                  { return 'Intune' }
        '^Unifi'                                                   { return 'UniFi' }
        '^Tailscale'                                               { return 'Tailscale' }
        '^App(Traces|Metrics|Requests|Dependencies|Exceptions|PageViews|PerformanceCounters|Events|SystemEvents|ServiceHTTPLogs|ServiceConsoleLogs|ServicePlatformLogs|ServiceFileAuditLogs|ServiceIPSecAuditLogs|ServiceAntivirusScanAuditLogs)$' { return 'Application Insights' }
        '^(LAQueryLogs|Usage|Heartbeat|Operation|Perf)$'           { return 'Workspace operations' }
        '^Dataverse'                                               { return 'Power Platform' }
        '_CL$'                                                     { return 'Custom (CCF / DCR)' }
        default                                                    { return 'Other' }
    }
}

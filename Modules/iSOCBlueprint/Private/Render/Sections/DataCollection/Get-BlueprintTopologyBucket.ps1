#Requires -Version 7.6

<#
.SYNOPSIS
    Name the topology group a table belongs to.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/DataCollection/Get-BlueprintTopologyBucket.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

# Topology flowchart — sourced from the synthesised $effective view
# rather than $connectors alone, so DCR-driven and diagnostic-settings-
# driven ingestion (the bulk of any modern workspace) appears too.
# Tables are grouped into source buckets via the same name-matching
# logic as the cost Sankey for consistency. Top 15 buckets render
# individually; anything beyond rolls up into "Other sources (N)".
function Get-BlueprintTopologyBucket {
    <#
    .SYNOPSIS
        Name the topology group a table belongs to.

    .DESCRIPTION
        A CCF source with an identifier is grouped under that identifier. A Classic
        source is grouped under the friendly title of its connector kind
        (Get-ConnectorFriendlyTitle, using the caller's $ccfTitleByName). Any other
        source is grouped by table name, and 'Other sources' when no pattern matches
        or the table is empty.

    .PARAMETER Table
        The table name.

    .PARAMETER Source
        How the table is fed: CCF or Classic.

    .PARAMETER Identifier
        For CCF, the group name itself; for Classic, 'kind/dataType'.

    .OUTPUTS
        [string].
    #>
    [CmdletBinding()]
    param([string]$Table, [string]$Source, [string]$Identifier)
    if ($Source -eq 'CCF' -and $Identifier) { return $Identifier }
    if ($Source -eq 'Classic') {
        # Identifier is "kind/dataType"; the friendly title comes from
        # the Get-ConnectorFriendlyTitle helper above. Strip to kind.
        $kind = ($Identifier -split '/')[0]
        return (Get-ConnectorFriendlyTitle -Kind $kind -Connector $null -CcfTitleByName $ccfTitleByName)
    }
    if (-not $Table) { return 'Other sources' }
    switch -Regex ($Table) {
        '^ThreatIntel'                                                                                  { return 'Microsoft Defender TI' }
        '^(SigninLogs|AuditLogs|AAD.*|MicrosoftGraphActivityLogs|MicrosoftServicePrincipalSignInLogs)$' { return 'Microsoft Entra ID' }
        '^(Device|Email|Url|Alert|Cloud|Identity).*'                                                    { return 'Microsoft Defender XDR' }
        '^ASim'                                                                                         { return 'ASIM normaliser' }
        '^Office'                                                                                       { return 'Office 365' }
        '^(CommonSecurityLog|Syslog)$'                                                                  { return 'CEF / Syslog' }
        '^(SecurityEvent|WindowsEvent|Event)$'                                                          { return 'Windows events' }
        '^(AzureActivity)$'                                                                             { return 'Azure Activity' }
        '^(AzureDiagnostics|AzureMetrics)$'                                                             { return 'Azure resource diagnostics' }
        '^Intune'                                                                                       { return 'Intune' }
        '^App'                                                                                          { return 'Application Insights' }
        '^Dataverse'                                                                                    { return 'Power Platform' }
        '^(LAQueryLogs|Usage|Heartbeat|Operation|Perf|SentinelAudit)$'                                  { return 'Workspace operations' }
        '_CL$'                                                                                          { return 'Custom logs (CCF / DCR)' }
        default                                                                                         { return 'Other sources' }
    }
}

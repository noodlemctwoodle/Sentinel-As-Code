#Requires -Version 7.2

<#
.SYNOPSIS
    Classify a data connector by its id: CCF, AzureFunctions, AMA, Platform, Agent or Legacy.

.DESCRIPTION
    A heuristic on the connector id's naming, as seen in the
    Azure-Sentinel Solutions Analyzer data.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/ClassicToDcr/Resolve-iSOCConnectorKind.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.0
    Last Updated: 2026-11-04
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Resolve-iSOCConnectorKind {
    <#
    .SYNOPSIS
        Classify a data connector by its id: CCF, AzureFunctions, AMA,
        Platform, Agent or Legacy.

    .DESCRIPTION
        A heuristic on the id's naming, as seen in the Azure-Sentinel
        Solutions Analyzer data, tested in this order:

          CCF             ends CCP, CCF, Definition, _Ccp_ or _Ccf_, or has
                          CCPDefinition: the Codeless Connector Framework
          AzureFunctions  Serverless, AzureFunction, Polling, PollingAuth,
                          ends Func, or _API_FunctionApp
          AMA             ends Ama: Azure Monitor Agent
          Platform        starts Azure, Office, Microsoft, Defender,
                          ThreatIntelligence, WindowsEvent or SecurityEvents
          Agent           CEF, Syslog or CefAma
          Legacy          anything else

        No id is Unknown.

    .PARAMETER ConnectorId
        The data connector's content id.

    .PARAMETER SolutionName
        The solution it belongs to. Not used yet; part of the contract for
        later heuristics.

    .OUTPUTS
        [string]

    .EXAMPLE
        Resolve-iSOCConnectorKind -ConnectorId 'OktaSSOv2'
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'SolutionName', Justification = 'Part of the classifier contract; callers pass solution context for later heuristics.')]
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string] $ConnectorId,

        [string] $SolutionName
    )

    $id = $ConnectorId
    if (-not $id) { return 'Unknown' }

    if ($id -match '(CCP|CCF|Definition|_Ccp_|_Ccf_)$' -or $id -match '(?i)CCPDefinition') { return 'CCF' }
    if ($id -match '(?i)(Serverless|AzureFunction|Polling|PollingAuth|Func$|_API_FunctionApp)') { return 'AzureFunctions' }
    if ($id -match '(?i)Ama$') { return 'AMA' }
    if ($id -match '^(Azure|Office|Microsoft|Defender|ThreatIntelligence|WindowsEvent|SecurityEvents)') { return 'Platform' }
    if ($id -match '(?i)^(CEF|Syslog|CefAma)$') { return 'Agent' }
    'Legacy'
}

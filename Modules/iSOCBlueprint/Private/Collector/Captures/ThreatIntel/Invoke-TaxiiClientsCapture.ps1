#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'taxii-clients': writes taxii-clients.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/ThreatIntel/Invoke-TaxiiClientsCapture.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Collector
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Invoke-TaxiiClientsCapture {
    <#
    .SYNOPSIS
        Capture 'taxii-clients': writes taxii-clients.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)

    $apiVersions = $Context.apiVersions
    $sentinelScope = $Context.sentinelScope

    # TAXII clients on the workspace's threat intelligence. The path is not in
    # the published REST reference, so it is tried on three api-versions and a
    # service that does not serve it leaves an empty list; the TI connectors
    # stay the primary feed signal on page 27.
    $clients = @()
    foreach ($v in @($apiVersions.Sentinel, '2024-03-01', '2023-11-01')) {
        try {
            $clients = Invoke-SentinelRest -Path "$sentinelScope/threatIntelligence/main/taxiiClients" -ApiVersion $v
            break
        } catch {
            $clients = @()
        }
    }
    Save-Json -FileName 'taxii-clients.json' -Data $clients
}

#Requires -Version 7.2

<#
.SYNOPSIS
    The name a managed API connector's connection resources are given.

.DESCRIPTION
    Copied from Get-ApiConnectorDisplayName (847ef86:Tools/Export-Playbooks.ps1).

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/Playbook/Get-iSOCApiConnectorDisplayName.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.0
    Last Updated: 2026-11-03
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCApiConnectorDisplayName {
    <#
    .SYNOPSIS
        Return the display name for a managed API (azuresentinel becomes
        MicrosoftSentinel), or the API name with a capital first letter.

    .PARAMETER ApiName
        The managed API's name.

    .OUTPUTS
        [string] The display name.

    .EXAMPLE
        Get-iSOCApiConnectorDisplayName -ApiName 'azuresentinel'
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $ApiName
    )

    $displayMap = @{
        'azuresentinel'                  = 'MicrosoftSentinel'
        'microsoftsentinel'              = 'MicrosoftSentinel'
        'wdatp'                          = 'MicrosoftDefenderXDR'
        'office365'                      = 'Office365'
        'teams'                          = 'MicrosoftTeams'
        'azuread'                        = 'AzureAD'
        'keyvault'                       = 'AzureKeyVault'
        'azureloganalytics'              = 'AzureLogAnalytics'
        'azuremonitorlogs'               = 'AzureMonitorLogs'
        'servicebus'                     = 'AzureServiceBus'
        'azureblob'                      = 'AzureBlobStorage'
        'sharepointonline'               = 'SharePointOnline'
        'cognitiveservicestextanalytics' = 'CognitiveServicesTextAnalytics'
        'microsoftgraphsecurity'         = 'MicrosoftGraphSecurity'
        'arm'                            = 'AzureResourceManager'
    }

    $lower = $ApiName.ToLowerInvariant()
    if ($displayMap.ContainsKey($lower)) { return $displayMap[$lower] }
    $ApiName.Substring(0, 1).ToUpperInvariant() + $ApiName.Substring(1)
}

#Requires -Version 7.2

<#
.SYNOPSIS
    Read a deployed data collection rule's immutable id and logs ingestion endpoint.

.DESCRIPTION
    What a sender needs to post to the rule.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/ClassicToDcr/Get-iSOCDcrIngestionEndpoint.ps1
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

function Get-iSOCDcrIngestionEndpoint {
    <#
    .SYNOPSIS
        Read a deployed data collection rule's immutable id and logs
        ingestion endpoint.

    .DESCRIPTION
        One GET of the rule. A Direct rule authored at 2023-03-11 or later
        has its own logsIngestion endpoint; one without needs a data
        collection endpoint. Either value is missing when the rule does not
        have it.

    .PARAMETER Context
        The workspace context.

    .PARAMETER DcrId
        The rule's resource id.

    .OUTPUTS
        [pscustomobject] ImmutableId and Endpoint.

    .EXAMPLE
        Get-iSOCDcrIngestionEndpoint -Context $ctx -DcrId $dcrId
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Context,

        [Parameter(Mandatory)]
        [string] $DcrId
    )

    $dcr = Invoke-iSOCRestRequest -Method GET -Path $DcrId -ApiVersion (Get-iSOCApiVersion DataCollectionRules) -Context $Context
    $immutableId = Get-iSOCPropertyValue -InputObject $dcr -Path 'properties.immutableId'
    $endpoint = Get-iSOCPropertyValue -InputObject $dcr -Path 'properties.endpoints.logsIngestion'
    [pscustomobject]@{
        ImmutableId = if ($null -ne $immutableId) { [string]$immutableId } else { $null }
        Endpoint    = if ($endpoint) { [string]$endpoint } else { $null }
    }
}

#Requires -Version 7.6

<#
.SYNOPSIS
    A data collection rule's immutable id and logs ingestion endpoint, or why it has none.

.DESCRIPTION
    Throws when the rule has no endpoint (it was not made Direct at
    2023-03-11 or later) or no immutable id (it has not finished
    provisioning).

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/Rehearsal/Get-iSOCDcrIngestionTarget.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCDcrIngestionTarget {
    <#
    .SYNOPSIS
        A data collection rule's immutable id and logs ingestion endpoint,
        or why it has none.

    .DESCRIPTION
        A rule has a logsIngestion endpoint only when it was made Direct at
        api-version 2023-03-11 or later, and one cannot be added afterwards,
        so a rule without throws, saying so. A rule without an immutable id
        has not finished provisioning, and throws too.

    .PARAMETER Dcr
        The rule, as ARM returns it.

    .OUTPUTS
        [pscustomobject] ImmutableId and Endpoint.

    .EXAMPLE
        Get-iSOCDcrIngestionTarget -Dcr $dcr
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [object] $Dcr
    )

    $immutableId = Get-iSOCPropertyValue -InputObject $Dcr -Path 'properties.immutableId'
    $endpoint = [string](Get-iSOCPropertyValue -InputObject $Dcr -Path 'properties.endpoints.logsIngestion')

    if ([string]::IsNullOrWhiteSpace($endpoint)) {
        throw 'This DCR has no logsIngestion endpoint. Endpoints exist only on DCRs created with kind Direct on api-version 2023-03-11 or later, and cannot be added afterwards. Recreate the DCR, or use a Data Collection Endpoint.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$immutableId)) {
        throw 'This DCR has no immutableId. It may not have finished provisioning.'
    }
    [pscustomobject]@{ ImmutableId = [string]$immutableId; Endpoint = $endpoint }
}

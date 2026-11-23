#Requires -Version 7.6

<#
.SYNOPSIS
    The table a rule sends a stream to.

.DESCRIPTION
    The data flow's outputStream without its Custom- or Microsoft- prefix.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/Rehearsal/Get-iSOCDcrDestinationTable.ps1
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

function Get-iSOCDcrDestinationTable {
    <#
    .SYNOPSIS
        The table a rule sends a stream to.

    .DESCRIPTION
        The outputStream of the data flow that takes the stream (else the
        first flow), without its Custom- or Microsoft- prefix:
        Custom-MyApp_CL is MyApp_CL. A flow without one sends to the stream's
        own name.

    .PARAMETER Dcr
        The rule, as ARM returns it.

    .PARAMETER Stream
        The stream.

    .OUTPUTS
        [string]

    .EXAMPLE
        Get-iSOCDcrDestinationTable -Dcr $dcr -Stream Custom-MyApp_CL
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [object] $Dcr,

        [Parameter(Mandatory)]
        [string] $Stream
    )

    $flowsValue = Get-iSOCPropertyValue -InputObject $Dcr -Path 'properties.dataFlows'
    $flows = @($flowsValue)
    $match = $flows | Where-Object { $streams = Get-iSOCPropertyValue -InputObject $_ -Path 'streams'; @($streams) -contains $Stream } | Select-Object -First 1
    if (-not $match) { $match = $flows | Select-Object -First 1 }
    $output = [string](Get-iSOCPropertyValue -InputObject $match -Path 'outputStream')
    if (-not $output) { $output = $Stream }
    $output -replace '^(Custom|Microsoft)-', ''
}

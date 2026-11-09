#Requires -Version 7.6

<#
.SYNOPSIS
    The columns a rule declares for a stream.

.DESCRIPTION
    A stream with no columns throws.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/Rehearsal/Get-iSOCDcrStreamColumn.ps1
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

function Get-iSOCDcrStreamColumn {
    <#
    .SYNOPSIS
        The columns a rule declares for a stream.

    .DESCRIPTION
        From the stream's declaration; a stream with no columns throws.

    .PARAMETER Dcr
        The rule, as ARM returns it.

    .PARAMETER Stream
        The stream.

    .OUTPUTS
        [object[]] name and type.

    .EXAMPLE
        Get-iSOCDcrStreamColumn -Dcr $dcr -Stream Custom-MyApp_CL
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [object] $Dcr,

        [Parameter(Mandatory)]
        [string] $Stream
    )

    $declarations = Get-iSOCPropertyValue -InputObject $Dcr -Path 'properties.streamDeclarations'
    $declaration = if ($declarations -and $declarations.PSObject.Properties[$Stream]) { $declarations.PSObject.Properties[$Stream].Value } else { $null }
    $columns = Get-iSOCPropertyValue -InputObject $declaration -Path 'columns'
    if (-not $columns) { throw "Stream '$Stream' has no column definitions." }
    @($columns)
}

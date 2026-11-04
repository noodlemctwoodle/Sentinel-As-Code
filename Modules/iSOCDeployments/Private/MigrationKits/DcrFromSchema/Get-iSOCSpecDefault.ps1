#Requires -Version 7.2

<#
.SYNOPSIS
    Read one optional default from a schema file's extra properties.

.DESCRIPTION
    The defaults Import-iSOCTableSpec returns as Extra.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/DcrFromSchema/Get-iSOCSpecDefault.ps1
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

function Get-iSOCSpecDefault {
    <#
    .SYNOPSIS
        Read one optional default from a schema file's extra properties.

    .DESCRIPTION
        Returns the value under Key in the Extra dictionary
        Import-iSOCTableSpec returns, or nothing when there is no such key.

    .PARAMETER Extra
        The dictionary.

    .PARAMETER Key
        The default's name: description, dcrName, location, plan,
        retentionInDays, totalRetentionInDays or transformKql.

    .OUTPUTS
        [object] The value, or nothing.

    .EXAMPLE
        Get-iSOCSpecDefault -Extra $spec.Extra -Key 'plan'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object] $Extra,

        [Parameter(Mandatory)]
        [string] $Key
    )

    if ($null -eq $Extra) { return $null }
    if (-not $Extra.Contains($Key)) { return $null }
    $Extra[$Key]
}

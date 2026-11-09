#Requires -Version 7.6

<#
.SYNOPSIS
    Turn a retired identifier token into the query column it names.

.DESCRIPTION
    Copied from ConvertTo-DetectionColumnName
    (Deploy/content/Deploy-DefenderDetections.ps1).

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/DefenderDetection/ConvertTo-iSOCDefenderDetectionColumn.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function ConvertTo-iSOCDefenderDetectionColumn {
    <#
    .SYNOPSIS
        accountObjectId becomes AccountObjectId; sha1 and sha256 become
        SHA1 and SHA256.

    .PARAMETER Identifier
        The identifier token from impactedAssets or responseActions.

    .OUTPUTS
        [string] The column name.

    .EXAMPLE
        ConvertTo-iSOCDefenderDetectionColumn -Identifier 'deviceId'
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Identifier
    )

    $token = $Identifier.Trim()
    switch ($token) {
        'sha1' { return 'SHA1' }
        'sha256' { return 'SHA256' }
    }
    $token.Substring(0, 1).ToUpperInvariant() + $token.Substring(1)
}

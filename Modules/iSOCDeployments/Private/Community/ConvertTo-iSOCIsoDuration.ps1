#Requires -Version 7.2

<#
.SYNOPSIS
    A shorthand duration (5m, 1h, 1d) as ISO 8601.

.DESCRIPTION
    Copied from ConvertTo-Iso8601Duration (Tools/Import-CommunityRules.ps1).

.NOTES
    File:         Modules/iSOCDeployments/Private/Community/ConvertTo-iSOCIsoDuration.ps1
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

function ConvertTo-iSOCIsoDuration {
    <#
    .SYNOPSIS
        Return PT5M, PT1H or P1D for 5m, 1h or 1d; anything else as it is.

    .PARAMETER Value
        The duration.

    .OUTPUTS
        [string] The duration.

    .EXAMPLE
        ConvertTo-iSOCIsoDuration '1h'
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Value
    )

    if ($Value -match '^(\d+)(m|h|d)$') {
        $number = [int]$Matches[1]
        switch ($Matches[2]) {
            'd' { return "P${number}D" }
            'h' { return "PT${number}H" }
            'm' { return "PT${number}M" }
        }
    }
    $Value
}

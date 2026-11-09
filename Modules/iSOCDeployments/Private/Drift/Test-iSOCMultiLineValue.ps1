#Requires -Version 7.6

<#
.SYNOPSIS
    Whether a drift value is shown as a block rather than inline.

.DESCRIPTION
    Copied from Test-IsMultiLine (Tools/Test-SentinelRuleDrift.ps1).

.NOTES
    File:         Modules/iSOCDeployments/Private/Drift/Test-iSOCMultiLineValue.ps1
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

function Test-iSOCMultiLineValue {
    <#
    .SYNOPSIS
        $true for a value with a line break or over 120 characters.

    .PARAMETER Value
        The value.

    .OUTPUTS
        [bool]

    .EXAMPLE
        Test-iSOCMultiLineValue $modification.Deployed
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Position = 0)]
        [AllowNull()]
        [object] $Value
    )

    if ($null -eq $Value) { return $false }
    $text = [string]$Value
    $text.IndexOf("`n") -ge 0 -or $text.Length -gt 120
}

#Requires -Version 7.6

<#
.SYNOPSIS
    Turn the API's trigger operator into the short form rule files use.

.DESCRIPTION
    Copied from ConvertTo-ShortTriggerOperator
    (Tools/Test-SentinelRuleDrift.ps1). The inverse of
    ConvertTo-iSOCTriggerOperator.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/AnalyticsRule/ConvertTo-iSOCShortTriggerOperator.ps1
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

function ConvertTo-iSOCShortTriggerOperator {
    <#
    .SYNOPSIS
        GreaterThan becomes gt, LessThan lt, Equal eq and NotEqual ne.

    .DESCRIPTION
        In any case. Anything else comes back as given; nothing comes back
        for an empty value.

    .PARAMETER Value
        The operator as the API spells it.

    .OUTPUTS
        [string]

    .EXAMPLE
        ConvertTo-iSOCShortTriggerOperator 'GreaterThan'
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    $map = @{
        'greaterthan' = 'gt'
        'lessthan'    = 'lt'
        'equal'       = 'eq'
        'notequal'    = 'ne'
    }
    $key = $Value.ToLowerInvariant()
    if ($map.ContainsKey($key)) { return $map[$key] }
    $Value
}

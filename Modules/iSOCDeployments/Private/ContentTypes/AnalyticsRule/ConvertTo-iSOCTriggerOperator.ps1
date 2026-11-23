#Requires -Version 7.6

<#
.SYNOPSIS
    Map the trigger operator a rule file uses to the one the API takes.

.DESCRIPTION
    Replaces the inline map in Deploy-CustomDetections
    (Deploy/content/Deploy-CustomContent.ps1) and Convert-TriggerOperator
    (Tools/Test-SentinelRuleDrift.ps1), which carried the same table.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/AnalyticsRule/ConvertTo-iSOCTriggerOperator.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-23
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function ConvertTo-iSOCTriggerOperator {
    <#
    .SYNOPSIS
        Return GreaterThan, LessThan, Equal or NotEqual for a short or long
        spelling.

    .DESCRIPTION
        The repository style guide writes gt, lt, eq and ne; the API takes
        GreaterThan, LessThan, Equal and NotEqual. Either spelling, in any
        case, maps to the API form. Anything else is returned as written so
        the API can reject it; an empty value returns nothing.

    .PARAMETER Value
        The operator from the rule file.

    .OUTPUTS
        [string]

    .EXAMPLE
        ConvertTo-iSOCTriggerOperator 'gt'

        Returns GreaterThan.
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
        'gt' = 'GreaterThan'; 'greaterthan' = 'GreaterThan'
        'lt' = 'LessThan'; 'lessthan' = 'LessThan'
        'eq' = 'Equal'; 'equal' = 'Equal'
        'ne' = 'NotEqual'; 'notequal' = 'NotEqual'
    }
    $key = $Value.ToLowerInvariant()
    if ($map.ContainsKey($key)) { return $map[$key] }
    $Value
}

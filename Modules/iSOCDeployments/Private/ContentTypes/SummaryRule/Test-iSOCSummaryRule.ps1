#Requires -Version 7.2

<#
.SYNOPSIS
    Validate handler for summary rules.

.DESCRIPTION
    The checks Deploy-CustomSummaryRules
    (Deploy/content/Deploy-CustomContent.ps1) makes before it sends a rule,
    in the same order and with the same messages. A missing field is
    reported instead of failing the rule, where strict mode made the script
    throw reading it (MIGRATION.md edit E9).

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/SummaryRule/Test-iSOCSummaryRule.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.0
    Last Updated: 2026-11-03
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Test-iSOCSummaryRule {
    <#
    .SYNOPSIS
        Say why a summary rule cannot be sent, if it cannot.

    .DESCRIPTION
        A rule needs name, query, binSize and destinationTable; binSize must
        be one Log Analytics allows, and the destination table a custom
        (_CL) one. The first problem found is the one reported. A file that
        does not parse is reported as such.

    .PARAMETER Item
        A repository item from Read-iSOCSummaryRuleRepo.

    .OUTPUTS
        [string] The problem; nothing when the rule can be sent.

    .EXAMPLE
        $issues = @(Test-iSOCSummaryRule -Item $item)
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Item
    )

    if ($Item.ParseError) { return $Item.ParseError }
    $rule = $Item.Data
    $binSize = Get-iSOCPropertyValue -InputObject $rule -Path 'binSize'
    $table = [string](Get-iSOCPropertyValue -InputObject $rule -Path 'destinationTable')
    $missing = -not (Get-iSOCPropertyValue -InputObject $rule -Path 'name') -or
    -not (Get-iSOCPropertyValue -InputObject $rule -Path 'query') -or
    $null -eq $binSize -or
    -not $table
    if ($missing) { return 'missing required fields (name, query, binSize, destinationTable).' }

    $validBinSizes = @(20, 30, 60, 120, 180, 360, 720, 1440)
    if ($validBinSizes -notcontains [int]$binSize) {
        return "invalid binSize '$binSize'. Allowed values: $($validBinSizes -join ', ')."
    }
    if (-not $table.EndsWith('_CL')) { return "destinationTable must end with '_CL' suffix." }
}

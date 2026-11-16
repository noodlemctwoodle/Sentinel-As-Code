#Requires -Version 7.6

<#
.SYNOPSIS
    Loads the cost estimate.

.DESCRIPTION
    Dot-source this file to define Get-SentinelCostEstimate and the functions
    it uses. They live one per file under Modules/iSOCBlueprint/Private/Cost:

      Get-SentinelCostEstimate.ps1   the entry point, with the description of
                                     the inputs, the output and the method
      Steps/     one step per part of the estimate, run in order and
                 sharing an estimate context
      Helpers/   JSON reading, the unit price lookup and the property sum

.NOTES
    File:         Modules/iSOCBlueprint/Engine/Private/Get-SentinelCostEstimate.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-05-06
    Version:      0.4.0
    Last Updated: 2026-11-16
    Requires:     PowerShell 7.6+

    This file loads functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# The estimate functions (the module's own Private/Cost, two folders up from
# here), defined in the caller's scope.
$costRoot = Join-Path $PSScriptRoot '..' '..' 'Private' 'Cost'
foreach ($costFile in Get-ChildItem -LiteralPath $costRoot -Filter '*.ps1' -File -Recurse | Sort-Object FullName) {
    . $costFile.FullName
}
Remove-Variable -Name costFile, costRoot -WhatIf:$false

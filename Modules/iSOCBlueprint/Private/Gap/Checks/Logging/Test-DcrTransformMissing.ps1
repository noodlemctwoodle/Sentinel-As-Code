#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-LOG-09: DCR transform missing on noisy custom table

.DESCRIPTION
    Gap check for rule SAC-LOG-09 (Resources/Data/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Logging/Test-DcrTransformMissing.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.2
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Gap Engine
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# ------------------------------------------------------------
# SAC-LOG-09, DCR transform missing on noisy custom table
# ------------------------------------------------------------
function Test-DcrTransformMissing {
    <#
    .SYNOPSIS
        Gap check SAC-LOG-09: DCR transform missing on noisy custom table

    .PARAMETER Inventory
        The inventory Get-SentinelGap builds from the raw files.

    .OUTPUTS
        $null when the rule passes; otherwise the finding New-Finding returns, with its
        Evidence and Detail.
    #>
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    $missing = @($Inventory.Dcrs | Where-Object {
        $flows = @(Get-PropOrDefault $_ 'properties.dataFlows' @())
        $hasCustom = $flows | Where-Object { (Get-PropOrDefault $_ 'outputStream' '') -match 'Custom-' }
        $hasTransform = $flows | Where-Object { (Get-PropOrDefault $_ 'transformKql' '') }
        ($hasCustom) -and (-not $hasTransform)
    })
    if ($missing.Count -gt 0) {
        return New-Finding -Evidence "$(Format-BlueprintPlural $missing.Count 'DCR') $(Select-GapWording $missing.Count 'targets' 'target') a custom table without transformKql." -Detail @{ Count = $missing.Count }
    }
    return $null
}

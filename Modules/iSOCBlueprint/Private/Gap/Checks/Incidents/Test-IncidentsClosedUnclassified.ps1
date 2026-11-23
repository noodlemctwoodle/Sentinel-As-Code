#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-INC-02: Incidents closed without a classification

.DESCRIPTION
    Gap check for rule SAC-INC-02 (Resources/Data/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Incidents/Test-IncidentsClosedUnclassified.ps1
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
# SAC-INC-02, Incidents closed without a classification
# ------------------------------------------------------------
function Test-IncidentsClosedUnclassified {
    <#
    .SYNOPSIS
        Gap check SAC-INC-02: Incidents closed without a classification

    .PARAMETER Inventory
        The inventory Get-SentinelGap builds from the raw files.

    .OUTPUTS
        $null when the rule passes; otherwise the finding New-Finding returns, with its
        Evidence and Detail.
    #>
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    if (@($Inventory.IncidentsSummary).Count -eq 0) { return $null }
    $row = $Inventory.IncidentsSummary[0]
    # ByClassification arrived with this rule; an older capture has nothing
    # to evaluate.
    $bagValue = Get-PropOrDefault $row 'ByClassification' $null
    if ($null -eq $bagValue) { return $null }
    $closed = ConvertTo-GapInt (Get-PropOrDefault $row 'Closed' 0)
    if ($closed -lt 10) { return $null }            # statistical floor, small samples lie
    $bag = Read-GapBag $bagValue
    $unclassified = [int]$bag['Undetermined'] + [int]$bag['Unclassified']
    $ratio = $unclassified / [double]$closed
    if ($ratio -le 0.5) { return $null }
    return New-Finding -Evidence "$(Format-BlueprintCount $unclassified) of $(Format-BlueprintCount $closed) closed incidents ($([math]::Round($ratio * 100, 0))%) were closed as Undetermined or with no classification. Without a true or false positive verdict, false-positive rates and rule tuning have nothing to work from." -Detail @{ Closed = $closed; Undetermined = [int]$bag['Undetermined']; Unclassified = [int]$bag['Unclassified']; ByClassification = $bag }
}

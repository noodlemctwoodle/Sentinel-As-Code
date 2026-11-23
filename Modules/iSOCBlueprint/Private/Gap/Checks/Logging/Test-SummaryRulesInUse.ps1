#Requires -Version 7.6

<#
.SYNOPSIS
    Gap check SAC-LOG-19: Summary rules not in use while high-volume tables are ingested

.DESCRIPTION
    Gap check for rule SAC-LOG-19 (Resources/Data/best-practices.json). Takes the inventory
    built by Get-SentinelGap and returns $null when the rule passes, or a finding
    with Evidence and Detail when it fires.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Checks/Logging/Test-SummaryRulesInUse.ps1
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
# SAC-LOG-19, Summary rules not in use while high-volume tables are ingested
# ------------------------------------------------------------
function Test-SummaryRulesInUse {
    <#
    .SYNOPSIS
        Gap check SAC-LOG-19: Summary rules not in use while high-volume tables are ingested

    .PARAMETER Inventory
        The inventory Get-SentinelGap builds from the raw files.

    .OUTPUTS
        $null when the rule passes; otherwise the finding New-Finding returns, with its
        Evidence and Detail.
    #>
    [CmdletBinding()] param([Parameter(Mandatory=$true)]$Inventory)
    if ($Inventory.RawFiles -notcontains 'summary-rules.json') { return $null }
    if (@($Inventory.SummaryRules | Where-Object { $null -ne $_ }).Count -gt 0) { return $null }
    $threshold = 50.0
    $volumes = Get-GapTableVolume30d $Inventory
    $big = @(
        $volumes.GetEnumerator() |
            Where-Object { (ConvertTo-GapPer30Days $_.Value $Inventory) -ge $threshold } |
            Sort-Object @{ Expression = 'Value'; Descending = $true }, Key
    )
    if ($big.Count -eq 0) { return $null }
    $names = @($big | ForEach-Object { "$($_.Key) ($(Format-BlueprintGb $_.Value) GB)" })
    return New-Finding -Evidence "No summary rules are configured, while $(Format-BlueprintPlural $big.Count 'table') $(Select-GapWording $big.Count `
            'ingests' 'ingest') $(Format-BlueprintCount $threshold) GB or more per 30 days: $($names -join ', ')." -Detail @{
        Tables = @($big | ForEach-Object { [pscustomobject]@{ Table = $_.Key; Gb30d = [math]::Round($_.Value, 2) } })
    }
}

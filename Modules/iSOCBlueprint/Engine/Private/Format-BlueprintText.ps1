#Requires -Version 7.6

<#
.SYNOPSIS
    One way to write a number, an amount, a date, a plural and a service's
    raw name in the Blueprint's text: the report pages, the findings and
    the dashboard read the same.

.DESCRIPTION
    The dashboard formats in the browser; the report pages and the findings
    are written here. These helpers follow the dashboard's rules so a figure
    reads the same wherever it appears:

      counts    thousands separators: 1,234,567
      GB        two decimal places with separators: 56,941.81 (a value
                below 0.01 reads <0.01); the caller adds the unit
      money     the currency's symbol, whole units from 1,000 and two
                places below, as the dashboard's fmtMoney: £137,356, £572.31
      dates     15 Oct 2026, or 15 Oct 2026 21:03 UTC with the time; month
                names are the invariant culture's (Sep, never Sept)
      plurals   1 table, 3 tables, never table(s)
      names     CamelCase API values in words (CredentialAccess reads
                Credential access), Azure regions and workspace SKUs by
                their portal names (uksouth reads UK South)

    Every helper returns its input as text when it cannot read it, and an
    empty string for $null, so a caller never prints "n/a" by accident.

    Dot-source this file to define the helpers. They live one per file under
    Modules/iSOCBlueprint/Private/Format:

      Numbers/   ConvertTo-BlueprintDouble, Format-BlueprintCount,
                 Format-BlueprintNumber, Format-BlueprintGb,
                 Format-BlueprintMoney
      Text/      Format-BlueprintDate, Format-BlueprintPlural,
                 ConvertTo-BlueprintWords
      Names/     Get-BlueprintRegionName, Get-BlueprintSkuName
      Data/      the invariant culture, the currency symbols, and the region
                 and SKU names

.NOTES
    File:         Modules/iSOCBlueprint/Engine/Private/Format-BlueprintText.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-15
    Version:      0.2.0
    Last Updated: 2026-11-16
    Requires:     PowerShell 7.6+

    This file loads functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# The formatting helpers (the module's own Private/Format, two folders up from
# here), defined in the caller's scope.
$formatRoot = Join-Path $PSScriptRoot '..' '..' 'Private' 'Format'
foreach ($formatFile in Get-ChildItem -LiteralPath $formatRoot -Filter '*.ps1' -File -Recurse | Sort-Object FullName) {
    . $formatFile.FullName
}
Remove-Variable -Name formatFile, formatRoot -WhatIf:$false

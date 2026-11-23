#Requires -Version 7.6

<#
.SYNOPSIS
    The values the text formatters share: the invariant culture and the currency symbols the dashboard prints.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Format/Data/BlueprintTextSettings.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.1.0
    Last Updated: 2026-11-16
    Component:    iSOC Blueprint, Blueprint text formatting
    Requires:     PowerShell 7.6+

    This file defines values rather than running.
#>

$script:BlueprintInvariant = [System.Globalization.CultureInfo]::InvariantCulture

# The symbols the dashboard's Intl.NumberFormat('en-GB') prints; any other
# currency reads as its code before the figure (SEK 1,250).
$script:BlueprintCurrencySymbol = @{
    GBP = '£'; EUR = '€'; USD = 'US$'; AUD = 'A$'; CAD = 'CA$'; NZD = 'NZ$'
    JPY = 'JP¥'; CNY = 'CN¥'; INR = '₹'; HKD = 'HK$'; BRL = 'R$'; MXN = 'MX$'; KRW = '₩'
}

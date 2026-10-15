#Requires -Version 7.2

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

.NOTES
    File:         Modules/iSOCBlueprint/Engine/Private/Format-BlueprintText.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-15
    Version:      0.1.0
    Last Updated: 2026-10-15
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

$script:BlueprintInvariant = [System.Globalization.CultureInfo]::InvariantCulture

function ConvertTo-BlueprintDouble {
    <#
    .SYNOPSIS
        A number from a number or a numeric string (invariant culture), or
        $null when it is neither.
    #>
    [CmdletBinding()]
    param([AllowNull()] $Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [double] -or $Value -is [int] -or $Value -is [long] -or $Value -is [decimal] -or $Value -is [single]) { return [double]$Value }
    $s = ([string]$Value).Trim()
    if (-not $s) { return $null }
    $d = 0.0
    if ([double]::TryParse($s, [System.Globalization.NumberStyles]::Float, $script:BlueprintInvariant, [ref]$d)) { return $d }
    $null
}

function Format-BlueprintCount {
    <#
    .SYNOPSIS
        A count with thousands separators: 13858711766 reads 13,858,711,766.

    .PARAMETER Value
        A number or numeric string. A fraction is rounded to a whole number.

    .OUTPUTS
        [string]; the input as text when it is not a number, '' for $null.
    #>
    [CmdletBinding()]
    param([AllowNull()] $Value)
    $d = ConvertTo-BlueprintDouble $Value
    if ($null -eq $d) { return $(if ($null -eq $Value) { '' } else { [string]$Value }) }
    [math]::Round($d, [System.MidpointRounding]::AwayFromZero).ToString('#,0', $script:BlueprintInvariant)
}

function Format-BlueprintNumber {
    <#
    .SYNOPSIS
        A number with thousands separators and a fixed number of decimal
        places: 1963.4 reads 1,963.40 at two places.

    .PARAMETER Value
        A number or numeric string.

    .PARAMETER Decimals
        Decimal places, 0 to 6. Defaults to 2.

    .OUTPUTS
        [string]; the input as text when it is not a number, '' for $null.
    #>
    [CmdletBinding()]
    param([AllowNull()] $Value, [ValidateRange(0, 6)] [int] $Decimals = 2)
    $d = ConvertTo-BlueprintDouble $Value
    if ($null -eq $d) { return $(if ($null -eq $Value) { '' } else { [string]$Value }) }
    $fmt = if ($Decimals -gt 0) { '#,0.' + ('0' * $Decimals) } else { '#,0' }
    [math]::Round($d, $Decimals, [System.MidpointRounding]::AwayFromZero).ToString($fmt, $script:BlueprintInvariant)
}

function Format-BlueprintGb {
    <#
    .SYNOPSIS
        A volume in GB as the dashboard writes it: two decimal places with
        thousands separators (56,941.81), <0.01 for a volume too small to
        show, 0.00 for none. The caller adds ' GB'.

    .PARAMETER Value
        GB, as a number or numeric string.

    .OUTPUTS
        [string]; the input as text when it is not a number, '' for $null.
    #>
    [CmdletBinding()]
    param([AllowNull()] $Value)
    $d = ConvertTo-BlueprintDouble $Value
    if ($null -eq $d) { return $(if ($null -eq $Value) { '' } else { [string]$Value }) }
    if ($d -gt 0 -and $d -lt 0.005) { return '<0.01' }
    Format-BlueprintNumber -Value $d -Decimals 2
}

# The symbols the dashboard's Intl.NumberFormat('en-GB') prints; any other
# currency reads as its code before the figure (SEK 1,250).
$script:BlueprintCurrencySymbol = @{
    GBP = '£'; EUR = '€'; USD = 'US$'; AUD = 'A$'; CAD = 'CA$'; NZD = 'NZ$'
    JPY = 'JP¥'; CNY = 'CN¥'; INR = '₹'; HKD = 'HK$'; BRL = 'R$'; MXN = 'MX$'; KRW = '₩'
}

function Format-BlueprintMoney {
    <#
    .SYNOPSIS
        An amount as the dashboard's fmtMoney writes it: the currency's
        symbol, whole units from 1,000 and two decimal places below
        (£137,356, £572.31, -£4.10).

    .PARAMETER Amount
        The amount, as a number or numeric string.

    .PARAMETER Currency
        The ISO 4217 code (GBP, USD, EUR). Without one the figure has no
        symbol.

    .OUTPUTS
        [string]; the input as text when it is not a number, '' for $null.
    #>
    [CmdletBinding()]
    param([AllowNull()] $Amount, [AllowNull()] [AllowEmptyString()] [string] $Currency)
    $d = ConvertTo-BlueprintDouble $Amount
    if ($null -eq $d) { return $(if ($null -eq $Amount) { '' } else { [string]$Amount }) }
    $places = if ([math]::Abs($d) -ge 1000) { 0 } else { 2 }
    $figure = Format-BlueprintNumber -Value ([math]::Abs($d)) -Decimals $places
    $code = ([string]$Currency).Trim().ToUpperInvariant()
    $sign = if ($d -lt 0 -and [double]$figure.Replace(',', '') -ne 0) { '-' } else { '' }
    if (-not $code) { return "$sign$figure" }
    if ($script:BlueprintCurrencySymbol.ContainsKey($code)) { return "$sign$($script:BlueprintCurrencySymbol[$code])$figure" }
    "$sign$code $figure"
}

function Format-BlueprintDate {
    <#
    .SYNOPSIS
        A date as the dashboard writes it: 15 Oct 2026, or with -Time
        15 Oct 2026 21:03 UTC. Always UTC; invariant month names.

    .PARAMETER Value
        A [datetime], a [datetimeoffset] or a date string (ISO 8601 and the
        like). A string with no zone is read as UTC.

    .PARAMETER Time
        Add the time of day (hours and minutes) and 'UTC'.

    .OUTPUTS
        [string]; the input as text when it is not a date, '' for $null.
    #>
    [CmdletBinding()]
    param([AllowNull()] $Value, [switch] $Time)
    if ($null -eq $Value) { return '' }
    $dt = $null
    if ($Value -is [datetime]) { $dt = $Value.ToUniversalTime() }
    elseif ($Value -is [datetimeoffset]) { $dt = $Value.UtcDateTime }
    else {
        $s = ([string]$Value).Trim()
        if (-not $s) { return '' }
        $parsed = [datetime]::MinValue
        $styles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
        if (-not [datetime]::TryParse($s, $script:BlueprintInvariant, $styles, [ref]$parsed)) { return $s }
        $dt = $parsed
    }
    if ($Time) { return $dt.ToString('d MMM yyyy HH:mm', $script:BlueprintInvariant) + ' UTC' }
    $dt.ToString('d MMM yyyy', $script:BlueprintInvariant)
}

function Format-BlueprintPlural {
    <#
    .SYNOPSIS
        A count and its noun, singular or plural as the count needs:
        1 table, 3 tables, 1,250 tables. Never table(s).

    .PARAMETER Count
        The count.

    .PARAMETER Singular
        The noun for one (table, rule, policy).

    .PARAMETER Plural
        The noun for any other count. Defaults to the singular plus 's'.

    .PARAMETER NoCount
        The noun alone, chosen by the count (for "the table" or "the
        tables" after a figure already given).

    .OUTPUTS
        [string]
    #>
    [CmdletBinding()]
    param([AllowNull()] $Count, [Parameter(Mandatory)] [string] $Singular, [string] $Plural, [switch] $NoCount)
    $n = ConvertTo-BlueprintDouble $Count
    if ($null -eq $n) { $n = 0 }
    $word = if ($n -eq 1) { $Singular } elseif ($Plural) { $Plural } else { "${Singular}s" }
    if ($NoCount) { return $word }
    "$(Format-BlueprintCount $n) $word"
}

function ConvertTo-BlueprintWords {
    <#
    .SYNOPSIS
        A CamelCase API value in words, first word capitalised:
        CredentialAccess reads Credential access, BenignPositive reads
        Benign positive, CommandAndControl reads Command and control. An
        acronym keeps its capitals (IPAddress reads IP address); a value
        with spaces, punctuation or in one word is returned as given.

    .PARAMETER Value
        The value.

    .OUTPUTS
        [string]
    #>
    [CmdletBinding()]
    param([AllowNull()] [AllowEmptyString()] [string] $Value)
    if (-not $Value) { return [string]$Value }
    if ($Value -cnotmatch '^[A-Za-z][A-Za-z0-9]*$' -or $Value -cnotmatch '[a-z][A-Z]|[A-Z]{2}[a-z]') { return $Value }
    $words = @([regex]::Split($Value, '(?<=[a-z0-9])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])'))
    $rest = @($words | Select-Object -Skip 1 | ForEach-Object { if ($_ -cmatch '^[A-Z]{2,}$') { $_ } else { $_.ToLowerInvariant() } })
    $first = $words[0]
    if ($first -cmatch '^[a-z]') { $first = $first.Substring(0, 1).ToUpperInvariant() + $first.Substring(1) }
    (@($first) + $rest) -join ' '
}

# Azure's public regions by the names the portal shows.
$script:BlueprintRegionName = @{
    eastus = 'East US'; eastus2 = 'East US 2'; centralus = 'Central US'; northcentralus = 'North Central US'
    southcentralus = 'South Central US'; westcentralus = 'West Central US'; westus = 'West US'; westus2 = 'West US 2'
    westus3 = 'West US 3'; canadacentral = 'Canada Central'; canadaeast = 'Canada East'; brazilsouth = 'Brazil South'
    brazilsoutheast = 'Brazil Southeast'; mexicocentral = 'Mexico Central'; chilecentral = 'Chile Central'
    northeurope = 'North Europe'; westeurope = 'West Europe'; uksouth = 'UK South'; ukwest = 'UK West'
    francecentral = 'France Central'; francesouth = 'France South'; germanywestcentral = 'Germany West Central'
    germanynorth = 'Germany North'; switzerlandnorth = 'Switzerland North'; switzerlandwest = 'Switzerland West'
    norwayeast = 'Norway East'; norwaywest = 'Norway West'; swedencentral = 'Sweden Central'; swedensouth = 'Sweden South'
    polandcentral = 'Poland Central'; italynorth = 'Italy North'; spaincentral = 'Spain Central'; austriaeast = 'Austria East'
    belgiumcentral = 'Belgium Central'; denmarkeast = 'Denmark East'; finlandcentral = 'Finland Central'
    greececentral = 'Greece Central'; eastasia = 'East Asia'; southeastasia = 'Southeast Asia'; japaneast = 'Japan East'
    japanwest = 'Japan West'; koreacentral = 'Korea Central'; koreasouth = 'Korea South'; australiaeast = 'Australia East'
    australiasoutheast = 'Australia Southeast'; australiacentral = 'Australia Central'; australiacentral2 = 'Australia Central 2'
    newzealandnorth = 'New Zealand North'; centralindia = 'Central India'; southindia = 'South India'; westindia = 'West India'
    jioindiawest = 'Jio India West'; jioindiacentral = 'Jio India Central'; indonesiacentral = 'Indonesia Central'
    malaysiawest = 'Malaysia West'; taiwannorth = 'Taiwan North'; uaenorth = 'UAE North'; uaecentral = 'UAE Central'
    qatarcentral = 'Qatar Central'; israelcentral = 'Israel Central'; saudiarabiaeast = 'Saudi Arabia East'
    southafricanorth = 'South Africa North'; southafricawest = 'South Africa West'
    usgovvirginia = 'US Gov Virginia'; usgovarizona = 'US Gov Arizona'; usgovtexas = 'US Gov Texas'
    chinanorth = 'China North'; chinaeast = 'China East'; chinanorth2 = 'China North 2'; chinaeast2 = 'China East 2'
    chinanorth3 = 'China North 3'; chinaeast3 = 'China East 3'
}

function Get-BlueprintRegionName {
    <#
    .SYNOPSIS
        An Azure region by the name the portal shows: uksouth reads UK
        South. A region not in the list is returned as given.

    .PARAMETER Region
        The region's programmatic name (any case, spaces ignored).

    .OUTPUTS
        [string]
    #>
    [CmdletBinding()]
    param([AllowNull()] [AllowEmptyString()] [string] $Region)
    if (-not $Region) { return [string]$Region }
    $key = ($Region -replace '\s', '').ToLowerInvariant()
    if ($script:BlueprintRegionName.ContainsKey($key)) { return $script:BlueprintRegionName[$key] }
    $Region
}

# Log Analytics workspace SKUs as the dashboard's Overview names them.
$script:BlueprintSkuName = @{
    PerGB2018 = 'Pay-as-you-go'; CapacityReservation = 'Commitment tier'; LACluster = 'Dedicated cluster'; Free = 'Free tier'
    Standalone = 'Standalone (legacy)'; PerNode = 'Per node (legacy)'; Premium = 'Premium (legacy)'; Standard = 'Standard (legacy)'
}

function Get-BlueprintSkuName {
    <#
    .SYNOPSIS
        A workspace SKU as the dashboard's Overview names it:
        CapacityReservation reads Commitment tier. An SKU not in the list
        is returned as given.

    .PARAMETER Sku
        The SKU name from the workspace's properties.sku.name.

    .OUTPUTS
        [string]
    #>
    [CmdletBinding()]
    param([AllowNull()] [AllowEmptyString()] [string] $Sku)
    if (-not $Sku) { return [string]$Sku }
    foreach ($k in $script:BlueprintSkuName.Keys) { if ($k -ieq $Sku) { return $script:BlueprintSkuName[$k] } }
    $Sku
}

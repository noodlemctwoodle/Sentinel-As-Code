#Requires -Version 7.2

<#
.SYNOPSIS
    Returns the effective USD per GB rate of a Sentinel pricing tier.

.NOTES
    File:         Content/Workbooks/SentinelDataLake/SdlMigrationExport/Private/Kql/Get-SdlPricingRate.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.2.0
    Last Updated: 2026-11-16
    Requires:     PowerShell 7.2+

    Defines one function, dot-sourced by Export-SdlMigrationWorkbook.ps1
    (deprecated; to be replaced by the iSOCDeployments module).
#>

# Keeps the file help above from being read as the help of the function below.

function Get-SdlPricingRate {
    <#
    .SYNOPSIS
        Returns the effective USD per GB rate of a Sentinel pricing
        tier.

    .DESCRIPTION
        Each commitment rate is the tier's daily price divided by its
        size, from the Azure Retail Prices API (service Sentinel,
        region eastus, read 2026-11-16). PAYG is the Pay-as-you-go
        Analysis meter, which in the simplified pricing tiers already
        includes Log Analytics ingestion. Other regions differ;
        callers pass -EffectiveAnalyticsRate for theirs.

    .PARAMETER Model
        PAYG or a commitment tier name (CT50 to CT50000). Unknown
        names fall back to PAYG.

    .OUTPUTS
        [double] The rate per GB.
    #>
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([double])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Model
    )

    switch ($Model) {
        'CT50' { return 3.225 }
        'CT100' { return 2.96 }
        'CT200' { return 2.74 }
        'CT300' { return 2.6667 }
        'CT400' { return 2.5933 }
        'CT500' { return 2.53 }
        'CT1000' { return 2.48 }
        'CT2000' { return 2.40 }
        'CT5000' { return 2.31 }
        'CT10000' { return 2.224 }
        'CT25000' { return 2.138 }
        'CT50000' { return 2.052 }
        default { return 4.30 }
    }
}

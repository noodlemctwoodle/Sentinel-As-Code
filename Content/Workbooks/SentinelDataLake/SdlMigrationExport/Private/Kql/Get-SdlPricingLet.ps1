#Requires -Version 7.6

<#
.SYNOPSIS
    Builds the KQL lets that carry every price and the retention-aware
    storage figures.

.NOTES
    File:         Content/Workbooks/SentinelDataLake/SdlMigrationExport/Private/Kql/Get-SdlPricingLet.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.2.0
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    Defines one function, dot-sourced by Export-SdlMigrationWorkbook.ps1
    (deprecated; to be replaced by the iSOCDeployments module).
#>

# Keeps the file help above from being read as the help of the function below.

function Get-SdlPricingLet {
    <#
    .SYNOPSIS
        Builds the KQL lets that carry every price and the
        retention-aware storage figures.

    .DESCRIPTION
        Besides the raw prices it derives three per-GB storage figures
        that follow Microsoft's retention billing (Manage data in
        Microsoft Sentinel and Defender; Plan costs, data lake tier).
        analyticsRetentionPerGB is analytics retention beyond the 90
        free days at the Log Analytics retention price (uncompressed
        GB-months). analyticsLakeStoragePerGB is lake storage for the
        days after analytics retention ends, which an Analytics-tier
        table pays when its total retention is longer (mirroring the
        analytics period is free). lakeOnlyStoragePerGB is lake
        storage for the whole retention, which a lake-only table pays.
        Lake storage is billed on compressed GB, so steady-state
        monthly cost is monthly GB x (days held / 30) / compression x
        price.

    .PARAMETER Settings
        The settings object.

    .OUTPUTS
        [string] The let statements.
    #>
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [object]$Settings
    )

    $modelRate = Get-SdlPricingRate -Model $Settings.PricingModel
    return @"
let userRate = toreal('$(Format-KqlNumber -Value $Settings.EffectiveAnalyticsRate)');
let modelRate = toreal('$(Format-KqlNumber -Value $modelRate)');
let priceAnalytics = iif(userRate > 0, userRate, modelRate);
let priceLakeIngest = toreal('$(Format-KqlNumber -Value $Settings.LakeIngestPricePerGB)');
let priceLakeProc = toreal('$(Format-KqlNumber -Value $Settings.LakeProcessingPricePerGB)');
let priceLakeStore = toreal('$(Format-KqlNumber -Value $Settings.LakeStoragePricePerGBMonth)');
let priceLakeQuery = toreal('$(Format-KqlNumber -Value $Settings.LakeQueryPricePerGB)');
let lakeRetentionDays = toreal('$(Format-KqlNumber -Value $Settings.TargetLakeRetentionDays)');
let compressionRatio = toreal('$(Format-KqlNumber -Value $Settings.CompressionRatio)');
let analyticsRetentionDays = toreal('$(Format-KqlNumber -Value $Settings.AnalyticsRetentionDays)');
let priceAnalyticsRetention = toreal('$(Format-KqlNumber -Value $Settings.AnalyticsRetentionPricePerGBMonth)');
let analyticsRetentionPerGB = max_of(analyticsRetentionDays - 90.0, 0.0) / 30.0 * priceAnalyticsRetention;
let analyticsLakeStoragePerGB = max_of(lakeRetentionDays - analyticsRetentionDays, 0.0) / 30.0 / compressionRatio * priceLakeStore;
let lakeOnlyStoragePerGB = lakeRetentionDays / 30.0 / compressionRatio * priceLakeStore;

"@
}

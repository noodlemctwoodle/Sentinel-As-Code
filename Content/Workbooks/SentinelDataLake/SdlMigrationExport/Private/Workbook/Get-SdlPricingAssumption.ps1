#Requires -Version 7.2

<#
.SYNOPSIS
    Builds the Pricing Assumptions row.

.NOTES
    File:         Content/Workbooks/SentinelDataLake/SdlMigrationExport/Private/Workbook/Get-SdlPricingAssumption.ps1
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

function Get-SdlPricingAssumption {
    <#
    .SYNOPSIS
        Builds the Pricing Assumptions row.

    .DESCRIPTION
        Every pricing and window input used by the run, with the
        script version and the source of the default prices, so the
        numbers are reproducible.

    .PARAMETER Settings
        The settings object.

    .PARAMETER Workspace
        The workspace name.

    .PARAMETER Subscription
        The subscription ID.

    .PARAMETER ResourceGroup
        The resource group name.

    .PARAMETER ScriptVersion
        The exporter version.

    .PARAMETER GeneratedAt
        When the run started.

    .OUTPUTS
        [pscustomobject] One row.
    #>
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)]
        [object]$Settings,

        [Parameter(Mandatory)]
        [string]$Workspace,

        [Parameter(Mandatory)]
        [string]$Subscription,

        [Parameter(Mandatory)]
        [string]$ResourceGroup,

        [Parameter(Mandatory)]
        [string]$ScriptVersion,

        [Parameter(Mandatory)]
        [datetime]$GeneratedAt
    )

    $effectiveRate = if ($Settings.EffectiveAnalyticsRate -gt 0) { $Settings.EffectiveAnalyticsRate } else { Get-SdlPricingRate -Model $Settings.PricingModel }
    [pscustomobject]@{
        ScriptVersion                = $ScriptVersion
        ScriptStatus                 = 'Deprecated - correctness fixes only'
        GeneratedAt                  = $GeneratedAt.ToString('u')
        Workspace                    = $Workspace
        Subscription                 = $Subscription
        ResourceGroup                = $ResourceGroup
        TimeRangeDays                = $Settings.TimeRangeDays
        QueryLookbackDays            = $Settings.QueryLookbackDays
        AlertActivityDays            = $Settings.AlertActivityDays
        XdrLookbackDays              = $Settings.XdrLookbackDays
        PricingModel                 = $Settings.PricingModel
        EffectiveAnalyticsRate_PerGB = $effectiveRate
        Currency                     = $Settings.Currency
        LakeIngestPricePerGB         = $Settings.LakeIngestPricePerGB
        LakeProcessingPricePerGB     = $Settings.LakeProcessingPricePerGB
        LakeStoragePricePerGBMonth   = $Settings.LakeStoragePricePerGBMonth
        LakeQueryPricePerGB          = $Settings.LakeQueryPricePerGB
        TargetLakeRetentionDays      = $Settings.TargetLakeRetentionDays
        AnalyticsRetentionDays       = $Settings.AnalyticsRetentionDays
        AnalyticsRetentionPerGBMonth = $Settings.AnalyticsRetentionPricePerGBMonth
        CompressionRatio             = $Settings.CompressionRatio
        PriceSource                  = 'Azure Retail Prices API, eastus, USD list, 2026-11-16'
    }
}

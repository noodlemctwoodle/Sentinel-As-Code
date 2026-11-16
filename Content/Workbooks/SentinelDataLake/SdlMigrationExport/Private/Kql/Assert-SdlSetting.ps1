#Requires -Version 7.2

<#
.SYNOPSIS
    Rejects settings that cannot be priced.

.NOTES
    File:         Content/Workbooks/SentinelDataLake/SdlMigrationExport/Private/Kql/Assert-SdlSetting.ps1
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

function Assert-SdlSetting {
    <#
    .SYNOPSIS
        Rejects settings that cannot be priced.

    .DESCRIPTION
        Total retention includes the analytics period, so the target
        retention cannot be shorter than the analytics retention.

    .PARAMETER Settings
        The settings object built by Export-SdlMigrationWorkbook.ps1.

    .OUTPUTS
        None. Throws when the settings are inconsistent.
    #>
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([void])]
    param (
        [Parameter(Mandatory)]
        [object]$Settings
    )

    if ($Settings.TargetLakeRetentionDays -lt $Settings.AnalyticsRetentionDays) {
        throw "TargetLakeRetentionDays ($($Settings.TargetLakeRetentionDays)) cannot be shorter than AnalyticsRetentionDays ($($Settings.AnalyticsRetentionDays)): total retention includes the analytics period."
    }
}

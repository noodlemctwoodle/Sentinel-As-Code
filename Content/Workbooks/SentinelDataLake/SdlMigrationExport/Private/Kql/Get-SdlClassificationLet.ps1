#Requires -Version 7.6

<#
.SYNOPSIS
    Builds the KQL lets that list the tables in each classification.

.NOTES
    File:         Content/Workbooks/SentinelDataLake/SdlMigrationExport/Private/Kql/Get-SdlClassificationLet.ps1
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

function Get-SdlClassificationLet {
    <#
    .SYNOPSIS
        Builds the KQL lets that list the tables in each
        classification.

    .DESCRIPTION
        The category lists match the workbook's most complete copies
        (Alert and Anomalies included); the Classic V1, DCR, Basic and
        Auxiliary lists come from the table inventory. Every cost
        query classifies through these lets and Get-SdlCategoryKql, so
        the sheets cannot drift apart.

    .PARAMETER Inventory
        The table inventory from Get-SdlTableInventory.

    .OUTPUTS
        [string] The let statements.
    #>
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [object]$Inventory
    )

    $classic = ConvertTo-KqlList -Item $Inventory.ClassicV1
    $dcr = ConvertTo-KqlList -Item $Inventory.DcrCustom
    $basic = ConvertTo-KqlList -Item $Inventory.BasicPlan
    $auxiliary = ConvertTo-KqlList -Item $Inventory.AuxiliaryPlan
    return @"
let notSupportedInLake = dynamic(['AzureDiagnostics','AzureMetrics','Alert']);
let sentinelFeatureTables = dynamic(['SecurityAlert','SecurityIncident','SecurityRecommendation','ThreatIntelligenceIndicator','ThreatIntelIndicators','ThreatIntelObjects','Watchlist','SentinelHealth','SentinelAudit','HuntingBookmark','SecurityBaseline','SecurityBaselineSummary']);
let uebaTables = dynamic(['BehaviorAnalytics','IdentityInfo','UserPeerAnalytics','BehaviorAnalyticsCloudActivityLogs','Anomalies']);
let systemTables = dynamic(['Heartbeat','Usage','Operation','LAQueryLogs','LASummaryLogs','ProtectionStatus','ComputerGroup']);
let classicV1Tables = dynamic([$classic]);
let dcrCustomTables = dynamic([$dcr]);
let basicPlanTables = dynamic([$basic]);
let auxiliaryPlanTables = dynamic([$auxiliary]);

"@
}

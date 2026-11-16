#Requires -Version 7.2

<#
.SYNOPSIS
    Lists Microsoft-retired tables that still receive data.

.NOTES
    File:         Content/Workbooks/SentinelDataLake/SdlMigrationExport/Private/Report/Get-SdlDeprecationReport.ps1
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

function Get-SdlDeprecationReport {
    <#
    .SYNOPSIS
        Lists Microsoft-retired tables that still receive data.

    .DESCRIPTION
        Microsoft stopped ingesting threat intelligence into the
        legacy ThreatIntelligenceIndicator table after 31 July 2025; a
        row appears only when the table still has billable data in the
        window.

    .PARAMETER Connection
        The connection object.

    .PARAMETER Settings
        The settings object.

    .OUTPUTS
        The Deprecation Warnings rows.
    #>
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([object])]
    param (
        [Parameter(Mandatory)]
        [object]$Connection,

        [Parameter(Mandatory)]
        [object]$Settings
    )

    $kql = @'
let deprecatedTables = datatable(LegacyTable:string, Replacement:string, Urgency:string, Reference:string)
[
    'ThreatIntelligenceIndicator',
        'ThreatIntelIndicators + ThreatIntelObjects',
        'Retired - Microsoft stopped ingesting threat intelligence into the legacy table after 31 July 2025',
        'https://learn.microsoft.com/azure/sentinel/work-with-stix-objects-indicators'
];
Usage
| where TimeGenerated > ago(__DAYS__d)
| where IsBillable == true
| summarize GBPerMonth = (sum(Quantity) / 1000.0 / toreal(__DAYS__)) * 30.0 by DataType
| join kind=inner (deprecatedTables) on $left.DataType == $right.LegacyTable
| project Table=DataType, DeprecationType='Table replaced', Replacement, Urgency, GBPerMonth=round(GBPerMonth, 2), DocsUrl=Reference
'@
    Invoke-SdlKqlQuery -Connection $Connection -Query (Expand-KqlTemplate -Template $kql -Settings $Settings)
}

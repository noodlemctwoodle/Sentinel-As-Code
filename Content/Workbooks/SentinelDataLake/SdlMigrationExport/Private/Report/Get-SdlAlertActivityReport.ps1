#Requires -Version 7.6

<#
.SYNOPSIS
    Summarises SecurityAlert activity per alert name.

.NOTES
    File:         Content/Workbooks/SentinelDataLake/SdlMigrationExport/Private/Report/Get-SdlAlertActivityReport.ps1
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

function Get-SdlAlertActivityReport {
    <#
    .SYNOPSIS
        Summarises SecurityAlert activity per alert name.

    .DESCRIPTION
        The workbook's grid: Critical counts as High, with medium and
        low counts, tactics and a criticality label. Returns nothing,
        with a warning, when the query fails.

    .PARAMETER Connection
        The connection object.

    .PARAMETER Settings
        The settings object.

    .OUTPUTS
        The Alert Activity rows.
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
SecurityAlert
| where TimeGenerated > ago(__ADAYS__d)
| summarize Alerts = count()
    , HighSeverity = countif(AlertSeverity in ('High','Critical'))
    , MediumSeverity = countif(AlertSeverity == 'Medium')
    , LowSeverity = countif(AlertSeverity in ('Low','Informational'))
    , LastSeen = max(TimeGenerated)
    , Tactics = strcat_array(make_set(Tactics, 5), ', ')
    by AlertName
| extend Criticality = case(
    HighSeverity > 0, 'High - keep in analytics',
    Alerts > 10, 'Medium - review before moving',
    Alerts > 0, 'Low - consider DCR split',
    'Dormant - safe to move')
| order by HighSeverity desc, Alerts desc
| project RuleOrAlertName=AlertName, Alerts, HighSeverity, MediumSeverity, LowSeverity, LastSeen, Tactics, Criticality
'@
    try {
        Invoke-SdlKqlQuery -Connection $Connection -Query (Expand-KqlTemplate -Template $kql -Settings $Settings)
    } catch {
        Write-Warning -Message "Alert activity skipped: $($_.Exception.Message)"
    }
}

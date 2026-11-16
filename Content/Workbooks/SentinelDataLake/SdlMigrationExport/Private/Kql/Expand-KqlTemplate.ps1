#Requires -Version 7.2

<#
.SYNOPSIS
    Substitutes the window and currency tokens in a KQL template.

.NOTES
    File:         Content/Workbooks/SentinelDataLake/SdlMigrationExport/Private/Kql/Expand-KqlTemplate.ps1
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

function Expand-KqlTemplate {
    <#
    .SYNOPSIS
        Substitutes the window and currency tokens in a KQL template.

    .DESCRIPTION
        The KQL templates are single-quoted here-strings so the KQL
        needs no PowerShell escaping. They carry __DAYS__, __QDAYS__,
        __XDAYS__, __ADAYS__ and __CUR__ tokens, replaced here from
        the settings.

    .PARAMETER Template
        The KQL text with tokens.

    .PARAMETER Settings
        The settings object.

    .OUTPUTS
        [string] The KQL ready to run.
    #>
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Template,

        [Parameter(Mandatory)]
        [object]$Settings
    )

    $text = $Template.Replace('__DAYS__', [string]$Settings.TimeRangeDays)
    $text = $text.Replace('__QDAYS__', [string]$Settings.QueryLookbackDays)
    $text = $text.Replace('__XDAYS__', [string]$Settings.XdrLookbackDays)
    $text = $text.Replace('__ADAYS__', [string]$Settings.AlertActivityDays)
    return $text.Replace('__CUR__', $Settings.Currency)
}

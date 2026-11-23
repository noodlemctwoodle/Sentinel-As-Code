#Requires -Version 7.6

<#
.SYNOPSIS
    Formats a number for KQL with the invariant culture.

.NOTES
    File:         Content/Workbooks/SentinelDataLake/SdlMigrationExport/Private/Kql/Format-KqlNumber.ps1
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

function Format-KqlNumber {
    <#
    .SYNOPSIS
        Formats a number for KQL with the invariant culture.

    .DESCRIPTION
        Default interpolation uses the thread culture, so 1.5 renders
        as "1,5" on de-DE or fr-FR machines and toreal() parses it
        wrongly. Every number that lands in KQL goes through this
        function.

    .PARAMETER Value
        The number to format.

    .OUTPUTS
        [string] The number with a decimal point.
    #>
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [double]$Value
    )

    return $Value.ToString([System.Globalization.CultureInfo]::InvariantCulture)
}

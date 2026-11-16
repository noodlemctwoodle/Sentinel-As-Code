#Requires -Version 7.2

<#
.SYNOPSIS
    Writes the deprecation notice for the exporter.

.NOTES
    File:         Content/Workbooks/SentinelDataLake/SdlMigrationExport/Private/Console/Write-SdlDeprecationNotice.ps1
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

function Write-SdlDeprecationNotice {
    <#
    .SYNOPSIS
        Writes the deprecation notice for the exporter.

    .DESCRIPTION
        The full notice is written at the start of a run; the short
        one-line form at the end, so it is still on screen after a
        long run.

    .PARAMETER Version
        The exporter version to quote.

    .PARAMETER Short
        Write the one-line form.

    .OUTPUTS
        None.
    #>
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([void])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Version,

        [Parameter()]
        [switch]$Short
    )

    if ($Short) {
        Write-Warning -Message "DEPRECATED: Export-SdlMigrationWorkbook (SdlMigrationExport v$Version) will be replaced by the iSOCDeployments PowerShell module. Exports from versions before 0.2.0 are not comparable with this one."
        return
    }
    Write-Warning -Message @"
DEPRECATED: Export-SdlMigrationWorkbook (SdlMigrationExport v$Version) is being retired and will be replaced by the iSOCDeployments PowerShell module.
  - It still works. Until the module takes over it only receives bug fixes.
  - Exports from versions before 0.2.0 are NOT comparable with this one: the default
    lake prices, the XDR, Query-Weighted and Alert Activity sheets and the rule
    counts all changed.
  - Details: Docs/Tools/SDL-Migration-Workbook-Export.md
"@
}

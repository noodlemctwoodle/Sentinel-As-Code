#Requires -Version 7.6

<#
.SYNOPSIS
    Root module of SdlMigrationExport (deprecated).

.DESCRIPTION
    Loads the private helpers and the one public command, then exports only
    that command by name. Import it with
    Import-Module ./Content/Workbooks/SentinelDataLake/SdlMigrationExport.

.NOTES
    File:         Content/Workbooks/SentinelDataLake/SdlMigrationExport/SdlMigrationExport.psm1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.2.0
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+
#>

Set-StrictMode -Version 'Latest'

foreach ($folder in @('Private', 'Public')) {
    $folderPath = Join-Path -Path $PSScriptRoot -ChildPath $folder
    foreach ($file in Get-ChildItem -LiteralPath $folderPath -Filter '*.ps1' -File -Recurse) {
        . $file.FullName
    }
}

# Named, never a wildcard: the helpers under Private stay internal.
Export-ModuleMember -Function 'Export-SdlMigrationWorkbook'

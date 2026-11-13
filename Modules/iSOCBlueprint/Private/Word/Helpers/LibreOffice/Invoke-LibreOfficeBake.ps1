#Requires -Version 7.6

<#
.SYNOPSIS
    Populate the Word TOC field's entries and page numbers through LibreOffice.

.DESCRIPTION
    Helper for the Word report conversion (Invoke-iSOCBlueprintWordConversion).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Word/Helpers/LibreOffice/Invoke-LibreOfficeBake.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, Word report
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Invoke-LibreOfficeBake {
    <#
    .SYNOPSIS
        Populate the Word TOC field's entries and page numbers in-place by
        driving LibreOffice headless through the UNO API (open hidden,
        update all indexes, save, close).

    .DESCRIPTION
        Pandoc emits a genuine Word TOC field but cannot paginate, so the
        field is empty until something computes page numbers. This delegates
        to Update-WordToc.py, which drives LibreOffice through the UNO API
        (the reliable headless method - a command-line Basic macro is
        documented as unreliable). Returns $true when the helper succeeds.

    .PARAMETER Soffice
        Path to the soffice/libreoffice executable (see Get-SofficePath).

    .PARAMETER DocxPath
        The .docx to update in place.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [string] $Soffice,
        [Parameter(Mandatory)] [string] $DocxPath
    )

    $helper = Join-Path $script:WordReportRoot 'Update-WordToc.py'
    if (-not (Test-Path -LiteralPath $helper)) {
        Write-WordLog "  Bake helper not found: $helper" -Level Warning
        return $false
    }
    $abs = (Resolve-Path -LiteralPath $DocxPath).Path
    $out = & python3 $helper $abs $Soffice 2>&1
    $ok = ($LASTEXITCODE -eq 0)
    foreach ($line in $out) { if ("$line".Trim()) { Write-WordLog "  uno: $line" -Level Info } }
    return $ok
}

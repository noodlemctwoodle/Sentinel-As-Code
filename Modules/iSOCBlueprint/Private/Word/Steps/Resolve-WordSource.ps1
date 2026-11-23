#Requires -Version 7.6

<#
.SYNOPSIS
    Check pandoc, resolve the source folder, title, output path and reference document.

.DESCRIPTION
    A step of the Word report conversion. Steps run in order and pass their results
    to later ones through the conversion context.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Word/Steps/Resolve-WordSource.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-16
    Component:    iSOC Blueprint, Word report
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Resolve-WordSource {
    <#
    .SYNOPSIS
        Check pandoc, resolve the source folder, title, output path and reference document.

    .PARAMETER Context
        The conversion context: the values earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the conversion context.
    $NoReferenceDoc = $Context.NoReferenceDoc
    $OutputPath = $Context.OutputPath
    $ReferenceDoc = $Context.ReferenceDoc
    $Source = $Context.Source
    $Title = $Context.Title
    $reportRoot = $Context.reportRoot

    Write-WordLog 'Markdown to Word report' -Level Section

    if (-not (Get-Command pandoc -ErrorAction SilentlyContinue)) {
        throw ("pandoc was not found on PATH. Install it and re-run:`n" +
            "  macOS    brew install pandoc`n" +
            "  Windows  winget install --id JohnMacFarlane.Pandoc`n" +
            '  Linux    sudo apt-get install pandoc')
    }

    if (-not (Test-Path -LiteralPath $Source)) { throw "Source path does not exist: $Source" }
    $sourceItem = Get-Item -LiteralPath $Source
    if (-not $sourceItem.PSIsContainer) { throw "Source must be a folder, not a file: $Source" }
    $sourceFull = $sourceItem.FullName

    if (-not $Title) { $Title = $sourceItem.Name }
    if (-not $OutputPath) {
        $OutputPath = Join-Path $sourceItem.Parent.FullName ($sourceItem.Name + '.docx')
    }
    $OutputPath = [System.IO.Path]::GetFullPath($OutputPath)

    # Default to the bundled, table-styled reference doc when present, unless
    # the caller opted out or supplied their own.
    if (-not $ReferenceDoc -and -not $NoReferenceDoc) {
        $bundled = Join-Path $reportRoot 'templates/sentinel-report-reference.docx'
        if (Test-Path -LiteralPath $bundled) { $ReferenceDoc = $bundled }
    }
    if ($NoReferenceDoc) { $ReferenceDoc = $null }
    if ($ReferenceDoc -and -not (Test-Path -LiteralPath $ReferenceDoc)) { throw "Reference document not found: $ReferenceDoc" }

    # Left in the conversion context for later steps.
    if (Get-Variable -Name 'OutputPath' -Scope 0 -ErrorAction Ignore) { $Context.OutputPath = $OutputPath }
    if (Get-Variable -Name 'ReferenceDoc' -Scope 0 -ErrorAction Ignore) { $Context.ReferenceDoc = $ReferenceDoc }
    $Context.sourceFull = $sourceFull
    if (Get-Variable -Name 'Title' -Scope 0 -ErrorAction Ignore) { $Context.Title = $Title }
}

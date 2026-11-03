#Requires -Version 7.2

<#
.SYNOPSIS
    Validate handler for workbooks.

.DESCRIPTION
    The check Deploy-CustomWorkbooks (Deploy/content/Deploy-CustomContent.ps1)
    makes before it builds a workbook, with the same message, then the
    metadata.json parse error the script failed the workbook over.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/Workbook/Test-iSOCWorkbook.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.0
    Last Updated: 2026-11-03
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Test-iSOCWorkbook {
    <#
    .SYNOPSIS
        Say why a workbook cannot be sent, if it cannot.

    .DESCRIPTION
        A workbook folder needs workbook.json; a metadata.json, when there
        is one, must parse. A missing template skips the workbook and a
        metadata.json that does not parse fails it.

    .PARAMETER Item
        A repository item from Read-iSOCWorkbookRepo.

    .OUTPUTS
        [string] The problem; nothing when the workbook can be sent.

    .EXAMPLE
        $issues = @(Test-iSOCWorkbook -Item $item)
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Item
    )

    if (-not (Test-Path -LiteralPath $Item.WorkbookPath -PathType Leaf)) { return 'workbook.json not found.' }
    if ($Item.ParseError) { return $Item.ParseError }
}

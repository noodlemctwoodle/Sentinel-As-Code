#Requires -Version 7.6

<#
.SYNOPSIS
    Write a text file the way every file the module writes is written.

.NOTES
    File:         Modules/iSOCDeployments/Private/Core/Write-iSOCTextFile.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Write-iSOCTextFile {
    <#
    .SYNOPSIS
        Write UTF-8 without a byte order mark, with LF line endings and one
        final newline.

    .DESCRIPTION
        Files the module writes into the repository come out the same on
        every platform, so a run on Windows does not rewrite every line
        ending. The folder is created when it is missing. The caller decides
        whether to write (ShouldProcess); this function always does.

    .PARAMETER Path
        The file to write.

    .PARAMETER Content
        The text. Existing CRLF line endings become LF and trailing newlines
        become one.

    .EXAMPLE
        Write-iSOCTextFile -Path $manifestPath -Content $json
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'The public command that calls it checks ShouldProcess; this is the write itself.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Content
    )

    $folder = Split-Path -Parent $Path
    if ($folder -and -not (Test-Path -LiteralPath $folder -PathType Container)) {
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
    }
    $text = $Content.Replace("`r`n", "`n").TrimEnd("`n") + "`n"
    [System.IO.File]::WriteAllText($Path, $text, [System.Text.UTF8Encoding]::new($false))
}

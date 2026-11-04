#Requires -Version 7.2

<#
.SYNOPSIS
    Clean free text from a pasted schema before it is written into an Azure resource.

.DESCRIPTION
    Descriptions and display names carry the paste damage ARM accepts and the
    portal then shows for ever.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/DcrFromSchema/ConvertTo-iSOCSafeText.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.0
    Last Updated: 2026-11-04
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function ConvertTo-iSOCSafeText {
    <#
    .SYNOPSIS
        Clean free text from a pasted schema before it is written into an
        Azure resource.

    .DESCRIPTION
        Control and format characters (line breaks, tabs, zero-width
        joiners, bidi marks) become spaces, runs of whitespace become one,
        and the result is trimmed and cut to MaxLength, ending '...'. The
        cap is the command's, so a pasted essay does not become a table
        description.

    .PARAMETER Text
        The text.

    .PARAMETER MaxLength
        The longest result; 256 unless given.

    .OUTPUTS
        [string] The cleaned text, or an empty string when there was nothing
        usable.

    .EXAMPLE
        ConvertTo-iSOCSafeText -Text $column.description
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [AllowNull()]
        [string] $Text,

        [int] $MaxLength = 256
    )

    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }

    $clean = [regex]::Replace($Text, '[\p{Cc}\p{Cf}]', ' ')
    $clean = [regex]::Replace($clean, '\s+', ' ').Trim()

    if ($clean.Length -gt $MaxLength) {
        $clean = $clean.Substring(0, $MaxLength - 3).TrimEnd() + '...'
    }
    $clean
}

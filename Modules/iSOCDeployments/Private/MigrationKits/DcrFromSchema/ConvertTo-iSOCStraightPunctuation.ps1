#Requires -Version 7.2

<#
.SYNOPSIS
    Replace curly quotes and no-break spaces with their ASCII equivalents.

.DESCRIPTION
    Word, wikis and chat clients substitute them as you type; JSON and KQL
    accept neither.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/DcrFromSchema/ConvertTo-iSOCStraightPunctuation.ps1
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

function ConvertTo-iSOCStraightPunctuation {
    <#
    .SYNOPSIS
        Replace curly quotes and no-break spaces with their ASCII
        equivalents.

    .DESCRIPTION
        Left and right double quotation marks become ", left and right single
        quotation marks become ', and a no-break space becomes a space. They
        look the same on screen and neither JSON nor KQL accepts them. The
        characters are written as code points, so this file stays ASCII.

    .PARAMETER Text
        The text.

    .OUTPUTS
        [string] The text with the substitutions made.

    .EXAMPLE
        ConvertTo-iSOCStraightPunctuation -Text $pasted
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    $substitutions = @(
        @{ From = [char]0x201C; To = '"' }
        @{ From = [char]0x201D; To = '"' }
        @{ From = [char]0x2018; To = "'" }
        @{ From = [char]0x2019; To = "'" }
        @{ From = [char]0x00A0; To = ' ' }
    )

    foreach ($substitution in $substitutions) {
        $Text = $Text.Replace([string]$substitution.From, $substitution.To)
    }
    $Text
}

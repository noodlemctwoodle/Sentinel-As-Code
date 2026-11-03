#Requires -Version 7.2

<#
.SYNOPSIS
    A content type's display name as it reads inside a sentence.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/Get-iSOCContentTypeNoun.ps1
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

function Get-iSOCContentTypeNoun {
    <#
    .SYNOPSIS
        Lower-case the display name's first letter, unless it starts with a
        name.

    .DESCRIPTION
        Display names are written to start a sentence ('Analytics rules').
        Inside one the first letter is lower-cased ('Deploying analytics
        rules...'), except when the first word is followed by another
        capitalised word, which marks a product name ('Defender XDR custom
        detections') that keeps its capital.

    .PARAMETER ContentType
        The content type.

    .OUTPUTS
        [string]

    .EXAMPLE
        Write-iSOCLog "Deploying $(Get-iSOCContentTypeNoun -ContentType $type)..."
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [psobject] $ContentType
    )

    $name = [string]$ContentType.DisplayName
    if ($name -cmatch '^[A-Z][a-z]+( [a-z]|$)') { return $name.Substring(0, 1).ToLowerInvariant() + $name.Substring(1) }
    $name
}

#Requires -Version 7.6

<#
.SYNOPSIS
    Clean Mermaid label text: drop wrapping double quotes and turn <br/> into a newline.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Mermaid/Helpers/ConvertTo-BpMermaidText.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-13
    Version:      0.1.2
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Mermaid chart parsing
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function ConvertTo-BpMermaidText {
    <#
    .SYNOPSIS
        Clean Mermaid label text: drop wrapping double quotes and turn <br/>
        into a newline.

    .DESCRIPTION
        The text is trimmed first. One pair of double quotes is removed, and
        only when the text both starts and ends with one. <br>, <br/> and
        <br /> each become a newline.

    .PARAMETER Text
        The label text.

    .OUTPUTS
        [string] The cleaned label.
    #>
    [CmdletBinding()]
    param([AllowEmptyString()] [AllowNull()] [string] $Text)
    if ($null -eq $Text) { return $null }
    $t = $Text.Trim()
    if ($t.Length -ge 2 -and $t.StartsWith('"') -and $t.EndsWith('"')) { $t = $t.Substring(1, $t.Length - 2) }
    return ($t -replace '<br\s*/?>', "`n")
}

#Requires -Version 7.2

<#
.SYNOPSIS
    The id a rule file declares.

.DESCRIPTION
    Copied from Get-RuleFileId (Tools/Import-CommunityRules.ps1).

.NOTES
    File:         Modules/iSOCDeployments/Private/Community/Get-iSOCRuleFileId.ps1
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

function Get-iSOCRuleFileId {
    <#
    .SYNOPSIS
        Return the top-level id of a rule YAML file, or nothing when the
        file is missing or has no id line.

    .DESCRIPTION
        Read from the text, quoted or bare, without parsing the file.

    .PARAMETER Path
        The rule file.

    .OUTPUTS
        [string] The id.

    .EXAMPLE
        Get-iSOCRuleFileId -Path $file
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $text = Get-Content -LiteralPath $Path -Raw -Encoding utf8
    if ([string]::IsNullOrEmpty($text)) { return $null }
    $match = [regex]::Match($text, '(?m)^id:[ \t]*[''"]?([^''"\r\n]+?)[''"]?[ \t]*$')
    if ($match.Success) { return $match.Groups[1].Value.Trim() }
    $null
}

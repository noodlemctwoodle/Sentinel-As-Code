#Requires -Version 7.2

<#
.SYNOPSIS
    Write a nested value as an indented YAML block.

.DESCRIPTION
    Copied from ConvertTo-IndentedSubtreeYaml in
    Tools/Test-SentinelRuleDrift.ps1, unchanged in behaviour apart from
    loading powershell-yaml itself.

.NOTES
    File:         Modules/iSOCDeployments/Private/Yaml/ConvertTo-iSOCYamlSubtree.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-23
    Version:      0.1.0
    Last Updated: 2026-10-23
    Requires:     PowerShell 7.2+

    Needs powershell-yaml when it runs. Import-iSOCYamlModule loads it
    then instead of #Requires, so the module imports without it.

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function ConvertTo-iSOCYamlSubtree {
    <#
    .SYNOPSIS
        Render an object with ConvertTo-Yaml and indent every line.

    .DESCRIPTION
        For the nested parts of a content file (entity mappings, grouping
        settings, incident configuration) that are written below a key. The
        trailing newline ConvertTo-Yaml adds is removed and empty lines stay
        empty.

    .PARAMETER Object
        The value to render.

    .PARAMETER Indent
        Spaces in front of every non-empty line. Default 0.

    .OUTPUTS
        [string] The block, lines joined with LF.

    .EXAMPLE
        "entityMappings:`n" + (ConvertTo-iSOCYamlSubtree -Object $mappings -Indent 2)
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [object] $Object,

        [int] $Indent = 0
    )

    Import-iSOCYamlModule
    $rendered = ConvertTo-Yaml $Object
    if (-not $rendered) { return '' }
    $rendered = $rendered.TrimEnd("`r", "`n")
    if ($Indent -le 0) { return $rendered }
    $prefix = ' ' * $Indent
    $lines = $rendered -split "`r?`n"
    $indented = foreach ($line in $lines) {
        if ($line.Length -gt 0) { "$prefix$line" } else { '' }
    }
    $indented -join "`n"
}

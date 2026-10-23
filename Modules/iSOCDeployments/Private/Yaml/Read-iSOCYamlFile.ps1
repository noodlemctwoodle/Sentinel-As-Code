#Requires -Version 7.2

<#
.SYNOPSIS
    Parse one YAML file.

.NOTES
    File:         Modules/iSOCDeployments/Private/Yaml/Read-iSOCYamlFile.ps1
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

function Read-iSOCYamlFile {
    <#
    .SYNOPSIS
        Return a YAML file's content as dictionaries and lists.

    .DESCRIPTION
        Mappings come back as hashtables, the shape the deployers read, or
        with -Ordered as ordered dictionaries that keep the file's key order
        for writers. An empty file returns nothing; a file that does not
        parse throws the parser's message.

    .PARAMETER Path
        The file to read.

    .PARAMETER Ordered
        Keep the key order of every mapping.

    .OUTPUTS
        [hashtable] or [System.Collections.Specialized.OrderedDictionary] for
        a mapping at the root; whatever the root is otherwise.

    .EXAMPLE
        $rule = Read-iSOCYamlFile -Path $file.FullName
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [switch] $Ordered
    )

    Import-iSOCYamlModule
    $text = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($text)) { return }
    if ($Ordered) { return (ConvertFrom-Yaml -Yaml $text -Ordered) }
    ConvertFrom-Yaml -Yaml $text
}

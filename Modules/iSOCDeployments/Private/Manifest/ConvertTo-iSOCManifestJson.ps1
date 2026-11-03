#Requires -Version 7.2

<#
.SYNOPSIS
    Write the dependency manifest as JSON.

.DESCRIPTION
    Copied from ConvertTo-OrderedManifestJson in
    Tools/Build-DependencyManifest.ps1, unchanged in behaviour.

.NOTES
    File:         Modules/iSOCDeployments/Private/Manifest/ConvertTo-iSOCManifestJson.ps1
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

function ConvertTo-iSOCManifestJson {
    <#
    .SYNOPSIS
        Serialise the entries under version, description and dependencies.

    .PARAMETER Entries
        The entries, from New-iSOCDependencyManifest.

    .PARAMETER Version
        The manifest format version.

    .PARAMETER Description
        The description line at the top of the file.

    .OUTPUTS
        [string] The JSON, indented as ConvertTo-Json writes it.

    .EXAMPLE
        ConvertTo-iSOCManifestJson -Entries $manifest.Entries -Version '1.0' -Description $text
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Entries,

        [Parameter(Mandatory)]
        [string] $Version,

        [Parameter(Mandatory)]
        [string] $Description
    )

    $manifest = [ordered]@{
        version      = $Version
        description  = $Description
        dependencies = $Entries
    }
    $manifest | ConvertTo-Json -Depth 32
}

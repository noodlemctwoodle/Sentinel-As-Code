#Requires -Version 7.6

<#
.SYNOPSIS
    Read the app id and version from the web part package.

.NOTES
    File:         Modules/iSOCBlueprint/Private/SharePoint/Apps/Get-SacAppPackageInfo.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, SharePoint site publisher
    Requires:     PowerShell 7.6+, PnP.PowerShell 3.4.1 (when the SharePoint functions are called)

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-SacAppPackageInfo {
    <#
    .SYNOPSIS
        Read the product id, version and title from an SPFx .sppkg.

    .DESCRIPTION
        An .sppkg is a zip with AppManifest.xml at its root. Its <App>
        element carries ProductID and Version, which is what the app
        catalog reports back, so the publisher can tell whether the
        deployed package is current without uploading it.

    .PARAMETER Path
        Path to the .sppkg file.

    .OUTPUTS
        [pscustomobject] ProductId (string, lower case), Version (string),
        Title (string).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)] [string] $Path)

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $Path).Path)
    try {
        $entry = $zip.Entries | Where-Object { $_.FullName -eq 'AppManifest.xml' } | Select-Object -First 1
        if (-not $entry) { throw "No AppManifest.xml in '$Path'; is it an SPFx .sppkg?" }
        $reader = [System.IO.StreamReader]::new($entry.Open())
        try { [xml]$manifest = $reader.ReadToEnd() } finally { $reader.Dispose() }
    } finally { $zip.Dispose() }

    $app = $manifest.App
    $title = if ($app.Properties -and $app.Properties.Title) { [string]$app.Properties.Title } else { [string]$app.Name }
    return [pscustomobject]@{
        ProductId = ([string]$app.ProductID).Trim('{}').ToLowerInvariant()
        Version   = [string]$app.Version
        Title     = $title
    }
}

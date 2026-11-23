#Requires -Version 7.6

<#
.SYNOPSIS
    Replace the ~site/ prefix the build uses with the web's server-relative URL.

.NOTES
    File:         Modules/iSOCBlueprint/Private/SharePoint/Site/Resolve-SacSiteUrl.ps1
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

function Resolve-SacSiteUrl {
    <#
    .SYNOPSIS
        Replace the '~site/' prefix the build uses with the web's
        server-relative URL.

    .PARAMETER Text
        HTML or a URL that may contain '~site/' tokens.

    .PARAMETER WebServerRelativeUrl
        The web's server-relative URL, for example '/sites/isoc-prod'.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Text,
        [Parameter(Mandatory)] [string] $WebServerRelativeUrl
    )
    $base = $WebServerRelativeUrl.TrimEnd('/')
    return $Text.Replace('~site/', "$base/")
}

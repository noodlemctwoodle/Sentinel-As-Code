#Requires -Version 7.6

<#
.SYNOPSIS
    Put the dashboard template back together from its parts.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Site/Helpers/Output/Get-SiteDashboardTemplate.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.1.2
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, SharePoint site build
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-SiteDashboardTemplate {
    <#
    .SYNOPSIS
        The dashboard page as one string, read from the parts under
        Resources/SharePoint/templates/dashboard.

    .DESCRIPTION
        The dashboard is one HTML page (its style, its markup and one
        script) kept as small files so each concern can be read and changed
        on its own. The parts are joined as they are, in the order of their
        paths relative to the folder (compared ordinally), so each name
        starts with a number: 01-head.html, 02-style/*.css, 03-body.html,
        04-script/*, 05-end.html. Only .html, .css and .js files are read;
        a part holds whole lines, so nothing is added between them.

        The result still holds the placeholders the site build fills in:
        __TITLE__, /*__MODEL__*/null and /*__SAC_CHARTS__*/.

    .PARAMETER Root
        The folder that holds the parts.

    .OUTPUTS
        [string]
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [string] $Root)

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        throw "The dashboard template folder is missing: $Root"
    }
    $rootFull = (Resolve-Path -LiteralPath $Root).ProviderPath
    $relative = [string[]]@(
        Get-ChildItem -LiteralPath $rootFull -File -Recurse |
            Where-Object { $_.Extension -in '.html', '.css', '.js' } |
            ForEach-Object { [System.IO.Path]::GetRelativePath($rootFull, $_.FullName).Replace('\', '/') }
    )
    if ($relative.Count -eq 0) { throw "The dashboard template folder holds no parts: $Root" }
    [System.Array]::Sort($relative, [System.StringComparer]::Ordinal)

    $text = [System.Text.StringBuilder]::new()
    foreach ($part in $relative) {
        [void]$text.Append([System.IO.File]::ReadAllText((Join-Path $rootFull $part), [System.Text.UTF8Encoding]::new($false)))
    }
    $text.ToString()
}

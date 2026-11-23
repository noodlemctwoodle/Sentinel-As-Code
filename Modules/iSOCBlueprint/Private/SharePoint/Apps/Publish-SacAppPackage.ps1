#Requires -Version 7.6

<#
.SYNOPSIS
    Upload the web part package to the app catalogue and deploy it.

.NOTES
    File:         Modules/iSOCBlueprint/Private/SharePoint/Apps/Publish-SacAppPackage.ps1
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

function Publish-SacAppPackage {
    <#
    .SYNOPSIS
        Deploy the dashboard web part's .sppkg to the site collection app
        catalog when the deployed version differs.

    .DESCRIPTION
        The package is built with skipFeatureDeployment, so publishing it
        to the site's own app catalog makes the web part available on this
        site immediately; no per-site install step is needed.

        SharePoint keeps one catalog file per solution id. A package with
        the same id under another title (the solution was renamed) makes
        the new upload an invalid package that never appears in
        AvailableApps, and Add-PnPApp then fails with "appMetadata". So any entry for this solution with
        another title is removed before the new package is added. The web
        part keeps its component id, so pages that use it pick it up again.

    .PARAMETER Path
        Path to the .sppkg.

    .OUTPUTS
        [string] The package version now deployed.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Progress for the operator at the console as the package is checked and deployed to the app catalog.')]
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param([Parameter(Mandatory)] [string] $Path)

    $info = Get-SacAppPackageInfo -Path $Path
    $ours = @(Get-SacCatalogApp | Where-Object {
            if ($_.ProductId) { $_.ProductId -eq $info.ProductId } else { $_.Title -eq $info.Title }
        })
    foreach ($app in $ours) {
        Write-Host "  In the app catalog: $($app.Title) $($app.Version)$(if (-not $app.Valid) { " (not accepted: $($app.Error))" })"
    }
    $stale = @($ours | Where-Object { $_.Title -ne $info.Title })
    $current = $ours | Where-Object { $_.Title -eq $info.Title -and $_.Valid } | Select-Object -First 1

    if ($stale.Count -eq 0 -and $current -and $current.Version -eq $info.Version -and -not $current.CanUpgrade) {
        Write-Host "  App package $($info.Version) already deployed."
        return $info.Version
    }
    $deployedText = if ($current) { "$($current.Title) $($current.Version)" } elseif ($stale.Count) { ($stale | ForEach-Object { "$($_.Title) $($_.Version)" }) -join ', ' } else { 'none' }
    if ($PSCmdlet.ShouldProcess("$($info.Title) $($info.Version) (deployed: $deployedText)", 'Deploy to site collection app catalog')) {
        foreach ($app in $stale) {
            Write-Host "  Removing '$($app.Title)' $($app.Version) from the app catalog; it is now '$($info.Title)'."
            Remove-PnPApp -Identity $app.Id -Scope Site | Out-Null
        }
        if ($stale.Count) {
            # Remove-PnPApp logs a refused removal on a no-script site and
            # returns, so check rather than trust it.
            $staleIds = @($stale | ForEach-Object { $_.Id })
            $left = @(Get-SacCatalogApp | Where-Object { $staleIds -contains $_.Id })
            if ($left.Count) {
                throw "Could not remove '$($left[0].Title)' from this site's app catalog. Remove it by hand (Site contents, Apps for SharePoint) and run the publish again."
            }
        }
        Add-PnPApp -Path $Path -Scope Site -Overwrite -Publish -SkipFeatureDeployment | Out-Null
        Write-Host "  Deployed app package $($info.Version)."
    }
    return $info.Version
}

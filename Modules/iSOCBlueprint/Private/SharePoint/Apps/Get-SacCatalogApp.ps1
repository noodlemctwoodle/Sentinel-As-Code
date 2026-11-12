#Requires -Version 7.6

<#
.SYNOPSIS
    Find the web part app in the site's app catalogue.

.NOTES
    File:         Modules/iSOCBlueprint/Private/SharePoint/Apps/Get-SacCatalogApp.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, SharePoint site publisher
    Requires:     PowerShell 7.6+, PnP.PowerShell 3.4.1 (when the SharePoint functions are called)

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function Get-SacCatalogApp {
    <#
    .SYNOPSIS
        List the site collection app catalog with the fields the deploy
        step needs.

    .DESCRIPTION
        Reads _api/web/sitecollectionappcatalog/AvailableApps directly
        because Get-PnPApp returns PnP Framework's AppMetadata, whose Id is
        the catalog item's id and which carries no product id. The REST
        response has both, plus whether SharePoint accepted the package.

    .OUTPUTS
        [pscustomobject], one per catalog entry: Id (catalog item id),
        ProductId ('' when not reported), Title, Version, CanUpgrade, Valid,
        Error. Ids are lower case without braces.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $response = Invoke-PnPSPRestMethod -Method Get -Url '/_api/web/sitecollectionappcatalog/AvailableApps' -ErrorAction Stop
    if ($response -is [string]) { $response = $response | ConvertFrom-Json }
    $items = if ($null -ne $response -and $response.PSObject.Properties['value']) { @($response.value) } else { @($response) }

    $items | Where-Object { $null -ne $_ } | ForEach-Object {
            $props = $_.PSObject.Properties
            [pscustomobject]@{
                Id         = ([string]$_.ID).Trim('{}').ToLowerInvariant()
                ProductId  = if ($props['ProductId'] -and $_.ProductId) { ([string]$_.ProductId).Trim('{}').ToLowerInvariant() } else { '' }
                Title      = [string]$_.Title
                Version    = [string]$_.AppCatalogVersion
                CanUpgrade = [bool]$_.CanUpgrade
                Valid      = if ($props['IsValidAppPackage']) { [bool]$_.IsValidAppPackage } else { $true }
                Error      = if ($props['ErrorMessage']) { [string]$_.ErrorMessage } else { '' }
            }
        }
}

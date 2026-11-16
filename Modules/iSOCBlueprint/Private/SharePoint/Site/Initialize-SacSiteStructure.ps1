#Requires -Version 7.6

<#
.SYNOPSIS
    Make sure the assets library and the findings list exist.

.NOTES
    File:         Modules/iSOCBlueprint/Private/SharePoint/Site/Initialize-SacSiteStructure.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-16
    Component:    iSOC Blueprint, SharePoint site publisher
    Requires:     PowerShell 7.6+, PnP.PowerShell 3.4.1 (when the SharePoint functions are called)

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function Initialize-SacSiteStructure {
    <#
    .SYNOPSIS
        Make sure the assets library, its folders and the findings list
        (with its columns) exist. Idempotent.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    if (-not (Get-PnPList -Identity $script:SacAssetsLibraryUrl -ErrorAction SilentlyContinue)) {
        if ($PSCmdlet.ShouldProcess($script:SacAssetsLibraryUrl, 'Create assets library')) {
            Invoke-SacCreateList -Url $script:SacAssetsLibraryUrl -Create {
                New-PnPList -Title $script:SacAssetsLibraryTitle -Template DocumentLibrary -Url $script:SacAssetsLibraryUrl -EnableVersioning | Out-Null
            } | Out-Null
        }
    }
    foreach ($folder in 'dashboard', 'diagrams', 'tables', '_state') {
        if ($PSCmdlet.ShouldProcess("$script:SacAssetsLibraryUrl/$folder", 'Ensure folder')) {
            Resolve-PnPFolder -SiteRelativePath "$script:SacAssetsLibraryUrl/$folder" | Out-Null
        }
    }

    $list = Get-PnPList -Identity $script:SacFindingsListUrl -ErrorAction SilentlyContinue
    if (-not $list) {
        if ($PSCmdlet.ShouldProcess($script:SacFindingsListUrl, 'Create findings list')) {
            $list = Invoke-SacCreateList -Url $script:SacFindingsListUrl -Create {
                New-PnPList -Title $script:SacFindingsListTitle -Template GenericList -Url $script:SacFindingsListUrl -EnableVersioning
            }
        }
    }
    if (-not $list) { return }

    foreach ($name in $script:SacFindingFields.Keys) {
        if (Get-PnPField -List $script:SacFindingsListUrl -Identity $name -ErrorAction SilentlyContinue) { continue }
        if ($PSCmdlet.ShouldProcess("$script:SacFindingsListUrl/$name", 'Add column')) {
            Add-PnPField -List $script:SacFindingsListUrl -DisplayName $name -InternalName $name -Type $script:SacFindingFields[$name] -AddToDefaultView |
                Out-Null
            if ($name -eq 'FindingId') {
                Set-PnPField -List $script:SacFindingsListUrl -Identity $name -Values @{ Indexed = $true } | Out-Null
            }
        }
    }
}

#Requires -Version 7.6

<#
.SYNOPSIS
    Stage 8: remove the pages and files the bundle no longer has, unless a page failed.

.DESCRIPTION
    A step of the SharePoint site publish. Steps run in order and pass their results
    to later ones through the publish context.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Publish/Steps/Invoke-PublishPrune.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, SharePoint site publisher
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Invoke-PublishPrune {
    <#
    .SYNOPSIS
        Stage 8: remove the pages and files the bundle no longer has, unless a page failed.

    .PARAMETER Context
        The publish context: the values earlier steps produced and this one adds to.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Reports each removal to the operator at the console as the publish runs.')]
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the publish context.
    $pageErrors = $Context.pageErrors
    $pagePlan = $Context.pagePlan
    $site = $Context.site
    $siteTables = $Context.siteTables

    # 8. Prune -------------------------------------------------------------------
    Write-PublishStep '8/8 Prune'
    if ($pageErrors.Count -gt 0) {
        Write-Host '  Skipped: some pages failed, so nothing is removed this run.' -ForegroundColor Yellow
    } else {
        foreach ($step in ($pagePlan | Where-Object Action -EQ 'Delete')) {
            Assert-TokenFresh "remove page $($step.Name)"
            if ($PSCmdlet.ShouldProcess("SitePages/$($step.Name).aspx", 'Send page to recycle bin')) {
                Remove-PnPPage -Identity $step.Name -Force -Recycle
                Write-Host "  Removed page: $($step.Name)"
            }
        }
        $stale = Get-AssetPrunePlan -DesiredFiles @($site.diagrams) -ExistingFiles (Get-SacFolderFileName -Folder 'diagrams')
        foreach ($file in $stale) {
            if ($PSCmdlet.ShouldProcess("$script:SacAssetsLibraryUrl/diagrams/$file", 'Send diagram to recycle bin')) {
                Remove-PnPFile -SiteRelativeUrl "$script:SacAssetsLibraryUrl/diagrams/$file" -Force -Recycle
            }
        }
        $staleTables = Get-AssetPrunePlan -DesiredFiles $siteTables -ExistingFiles (Get-SacFolderFileName -Folder 'tables')
        foreach ($file in $staleTables) {
            if ($PSCmdlet.ShouldProcess("$script:SacAssetsLibraryUrl/tables/$file", 'Send table CSV to recycle bin')) {
                Remove-PnPFile -SiteRelativeUrl "$script:SacAssetsLibraryUrl/tables/$file" -Force -Recycle
            }
        }
        Write-Host "  Pages removed: $(@($pagePlan | Where-Object Action -EQ 'Delete').Count)   Diagrams removed: $($stale.Count)   Table CSVs removed: $($staleTables.Count)"

        # The assets library's pre-Blueprint name. Its state files were read as
        # a fallback at the start of this run and are saved to the new library
        # below, and the dashboard now points at the new library, so it can go.
        if (Get-PnPList -Identity $script:SacLegacyAssetsLibraryUrl -ErrorAction SilentlyContinue) {
            if ($PSCmdlet.ShouldProcess($script:SacLegacyAssetsLibraryUrl, 'Send the old assets library to the recycle bin')) {
                Remove-PnPList -Identity $script:SacLegacyAssetsLibraryUrl -Recycle -Force | Out-Null
                Write-Host "  Old assets library '$script:SacLegacyAssetsLibraryUrl' sent to the recycle bin."
            }
        }
    }
}

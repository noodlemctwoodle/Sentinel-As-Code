#Requires -Version 7.6

<#
.SYNOPSIS
    Resolve the source folder, read the run context and settle the names and output folder.

.DESCRIPTION
    A step of the SharePoint site build. Steps run in order and pass their results
    to later ones through the build context.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Site/Steps/Initialize-SiteBuild.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, SharePoint site build
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Initialize-SiteBuild {
    <#
    .SYNOPSIS
        Resolve the source folder, read the run context and settle the names and output folder.

    .PARAMETER Context
        The build context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the build context.
    $OutputRoot = $Context.OutputRoot
    $ProductName = $Context.ProductName
    $Source = $Context.Source
    $Title = $Context.Title
    $WorkspaceName = $Context.WorkspaceName

    $Source = (Resolve-Path -LiteralPath $Source).Path
    $script:RawRoot = Join-Path $Source '_raw'
    if (-not (Test-Path -LiteralPath $script:RawRoot)) {
        throw "No _raw/ folder under '$Source'. Point -Source at a Blueprint workspace folder (the one containing _raw/)."
    }

    $runCtx = Read-SiteRaw 'run-context.json'
    # The window the KQL captures read: the lookback and the recent window
    # within it (run-context.json); a run collected before the setting existed
    # read 30 days and 7. The dashboard names every card's window from it.
    $lookbackDays = 30
    if ($runCtx -and $runCtx.PSObject.Properties['LookbackDays'] -and [int]$runCtx.LookbackDays -ge 1) { $lookbackDays = [int]$runCtx.LookbackDays }
    $recentDays = [math]::Min(7, $lookbackDays)
    if ($runCtx -and $runCtx.PSObject.Properties['RecentDays'] -and [int]$runCtx.RecentDays -ge 1) { $recentDays = [int]$runCtx.RecentDays }
    if (-not $WorkspaceName) {
        $WorkspaceName = if ($runCtx -and $runCtx.WorkspaceName) { $runCtx.WorkspaceName } else { Split-Path $Source -Leaf }
    }
    if (-not $Title) { $Title = "$WorkspaceName - $ProductName" }
    if (-not $OutputRoot) { $OutputRoot = Join-Path $Source 'sharepoint' }

    Write-SiteLog "iSOC Blueprint -> SharePoint site bundle" Section
    Write-SiteLog "  Source     : $Source"
    Write-SiteLog "  Workspace  : $WorkspaceName"
    Write-SiteLog "  Product    : $ProductName"
    Write-SiteLog "  Output     : $OutputRoot"

    $buildWarnings = [System.Collections.Generic.List[string]]::new()

    # Left in the build context for later steps.
    $Context.buildWarnings = $buildWarnings
    $Context.lookbackDays = $lookbackDays
    if (Get-Variable -Name 'OutputRoot' -Scope 0 -ErrorAction Ignore) { $Context.OutputRoot = $OutputRoot }
    $Context.recentDays = $recentDays
    $Context.runCtx = $runCtx
    $Context.Source = $Source
    if (Get-Variable -Name 'Title' -Scope 0 -ErrorAction Ignore) { $Context.Title = $Title }
    if (Get-Variable -Name 'WorkspaceName' -Scope 0 -ErrorAction Ignore) { $Context.WorkspaceName = $WorkspaceName }
}

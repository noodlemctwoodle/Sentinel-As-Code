#Requires -Version 7.2

<#
.SYNOPSIS
    The few lines New-iSOCBlueprint prints when a run is done.

.DESCRIPTION
    Each step logs as it goes; this is the run at a glance once they have
    all finished: how long it took, where it went, what the collection
    could not read and why, and what each format produced. Captures the
    identity had no permission for are listed apart from failures, because
    under an identity without every role they are expected.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Write-iSOCBlueprintRunSummary.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-15
    Version:      0.1.0
    Last Updated: 2026-10-15
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Write-iSOCBlueprintRunSummary {
    <#
    .SYNOPSIS
        Write the end-of-run summary to the host.

    .PARAMETER Path
        The run's folder (the one holding _raw).

    .PARAMETER Elapsed
        How long the run took.

    .PARAMETER Collected
        Whether this run collected the inventory, rather than reusing one.

    .PARAMETER WordDocument
        The Word document written, if any.

    .PARAMETER SiteBundle
        The SharePoint bundle folder written, if any.

    .PARAMETER SiteUrl
        The site the bundle was published to, if any.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [timespan] $Elapsed = [timespan]::Zero,
        [bool] $Collected = $true,
        [AllowNull()] [object] $WordDocument,
        [AllowNull()] [string] $SiteBundle,
        [AllowNull()] [string] $SiteUrl
    )

    $row = { param([string] $Name, [string] $Value) '  {0,-12}{1}' -f $Name, $Value }
    $readJson = {
        param([string] $File)
        if (-not (Test-Path -LiteralPath $File -PathType Leaf)) { return $null }
        try { Get-Content -LiteralPath $File -Raw | ConvertFrom-Json -Depth 32 } catch { $null }
    }
    $prop = { param($Object, [string] $Name) if ($null -ne $Object -and $Object.PSObject.Properties[$Name]) { $Object.$Name } else { $null } }
    # A path under the run's folder is shown relative to it.
    $short = {
        param([string] $Full)
        $rel = [System.IO.Path]::GetRelativePath($Path, $Full)
        if ($rel.StartsWith('..') -or [System.IO.Path]::IsPathRooted($rel)) { $Full } else { $rel }
    }

    $took = if ($Elapsed.TotalHours -ge 1) { '{0}h {1:00}m' -f [int][math]::Floor($Elapsed.TotalHours), $Elapsed.Minutes }
        elseif ($Elapsed.TotalMinutes -ge 1) { '{0}m {1:00}s' -f $Elapsed.Minutes, $Elapsed.Seconds }
        else { '{0}s' -f [int][math]::Ceiling($Elapsed.TotalSeconds) }

    Write-Host ''
    Write-Host "iSOC Blueprint finished in $took" -ForegroundColor Green
    Write-Host (& $row 'Folder' $Path)

    $raw = Join-Path $Path '_raw'
    $files = @(Get-ChildItem -LiteralPath $raw -Filter '*.json' -File -ErrorAction SilentlyContinue).Count
    if ($Collected) {
        $issues = @(& $prop (& $readJson (Join-Path $raw 'run-context.json')) 'CaptureIssues' | Where-Object { $_ })
        $permission = @($issues | Where-Object { (& $prop $_ 'Kind') -eq 'Permission' } | ForEach-Object { [string](& $prop $_ 'Label') } | Select-Object -Unique)
        $failed = @($issues | Where-Object { (& $prop $_ 'Kind') -ne 'Permission' } | ForEach-Object { [string](& $prop $_ 'Label') } | Select-Object -Unique)
        Write-Host (& $row 'Captures' "$files files written")
        if ($permission.Count) {
            Write-Host (& $row '' "$($permission.Count) not read in full, no permission (expected without the role): $($permission -join ', ')")
        }
        if ($failed.Count) {
            Write-Host (& $row '' "$($failed.Count) failed: $($failed -join ', ')") -ForegroundColor Yellow
        }
        if ($permission.Count -or $failed.Count) {
            Write-Host (& $row '' 'The capture summary above has each message.')
        }
    } else {
        Write-Host (& $row 'Captures' "$files files, reused (-SkipCollection)")
    }

    $pages = @(Get-ChildItem -LiteralPath $Path -Filter '*.md' -File -ErrorAction SilentlyContinue | Where-Object Name -ne 'index.md').Count
    $sections = @(Get-ChildItem -LiteralPath (Join-Path $Path 'sections') -Filter '*.json' -File -ErrorAction SilentlyContinue | Where-Object Name -ne 'index.json').Count
    $report = @()
    if ($pages) { $report += "$pages Markdown pages" }
    if ($sections) { $report += "$sections JSON sections" }
    if ($report.Count) { Write-Host (& $row 'Report' ($report -join ', ')) }

    if ($WordDocument) { Write-Host (& $row 'Word' (& $short ([string]$(if ($WordDocument -is [System.IO.FileInfo]) { $WordDocument.FullName } else { $WordDocument })))) }

    if ($SiteBundle) {
        $site = & $readJson (Join-Path $SiteBundle 'site.json')
        $detail = @()
        $siteSections = & $prop $site 'sections'
        if ($null -ne $siteSections) { $detail += "$(@($siteSections).Count) pages" }
        $findings = & $prop (& $prop $site 'summary') 'findings'
        if ($null -ne $findings) { $detail += "$findings findings" }
        $where = if ($SiteUrl) { "published to $SiteUrl" } else { 'not published (no -SiteUrl)' }
        $bundleShown = & $short $SiteBundle
        $text = if ($detail.Count) { "$bundleShown ($($detail -join ', ')), $where" } else { "$bundleShown, $where" }
        Write-Host (& $row 'SharePoint' $text)
    }
    Write-Host ''
}

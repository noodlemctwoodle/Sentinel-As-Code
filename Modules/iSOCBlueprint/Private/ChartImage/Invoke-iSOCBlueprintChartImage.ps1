#Requires -Version 7.6

<#
.SYNOPSIS
    Pre-render the Mermaid fences in the Blueprint's Markdown to image files
    and rewrite them as image references.

.NOTES
    File:         Modules/iSOCBlueprint/Private/ChartImage/Invoke-iSOCBlueprintChartImage.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-05-14
    Version:      0.2.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, chart images
    Requires:     PowerShell 7.6+, Node.js, @mermaid-js/mermaid-cli

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Invoke-iSOCBlueprintChartImage {
    <#
    .SYNOPSIS
        Pre-render Mermaid fenced blocks in the Markdown output to standalone
        image files (PNG by default) and rewrite the blocks as image
        references.

    .DESCRIPTION
        This is an Azure DevOps-only workaround. ADO Repos' markdown preview and
        ADO's "publish code as wiki" render ```mermaid``` fences as plain code, not
        diagrams. ADO Wiki proper renders some Mermaid but lags the spec and drops
        the experimental chart types we emit (xychart-beta, sankey-beta). On top of
        that, ADO blocks inline SVG images for security, so an SVG <img> shows as a
        broken image.

        PNG sidesteps both problems, it renders on every ADO markdown surface
        (Repos preview, code-wiki, project wiki), so PNG is the default output.

        GitHub renders ```mermaid``` fences natively, so the GitHub Actions workflow
        does NOT run this step and ships the raw fences. Only the ADO pipeline
        pre-renders, gated behind its prerenderChartsToPng parameter.

        After the renderer produces SecurityDocs/<workspace>/*.md, this function walks
        every markdown file, extracts each fenced ```mermaid block, runs it through
        `@mermaid-js/mermaid-cli` (mmdc), and rewrites the fenced block as
        `![Diagram](assets/<hash>.<ext>)`.

        The asset filename is the first 12 chars of the SHA-256 hash of the Mermaid
        body, so identical diagrams across files share one image and re-runs are
        idempotent (already-rendered hashes are reused).

        mmdc failures are warnings, the offending fenced block is left as-is so a
        syntax error on one chart never breaks the whole doc set.

    .PARAMETER Root
        Root directory containing per-workspace folders (e.g. SecurityDocs/).
        Each subfolder is treated as an isolated docset with its own
        assets/<hash>.<ext> sidecar directory.

    .PARAMETER Format
        Output image format: 'png' (default) or 'svg'. PNG is required for ADO;
        SVG is smaller and scalable but only renders on hosts that allow it
        (e.g. GitHub), which never receive these docs.

    .PARAMETER AssetsDir
        Name of the per-workspace asset folder. Defaults to 'assets'.

    .PARAMETER Theme
        mmdc theme. 'default' / 'dark' / 'forest' / 'neutral'. Defaults to
        'default' so the dark chart text stays legible on a solid light
        background.

    .PARAMETER Background
        mmdc background. Defaults to 'white' so a PNG is self-contained and
        readable on both light and dark Markdown hosts. (A transparent
        dark-theme chart would be invisible on ADO's light page, and ADO
        blocks transparent SVG anyway.)

    .PARAMETER Width
        mmdc render width in pixels. Defaults to 1400 to match the wider
        charts we already emit (MITRE, XDR bar).

    .PARAMETER Scale
        mmdc output scale factor (PNG only) for retina sharpness. Defaults to 2.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Progress and the summary for the operator at the console; the ##[section] line is a pipeline logging command that must reach the host stream.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Theme', Justification = 'Read inside the Regex.Replace script block that runs mmdc, which the analyser does not follow.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Background', Justification = 'Read inside the Regex.Replace script block that runs mmdc, which the analyser does not follow.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Width', Justification = 'Read inside the Regex.Replace script block that runs mmdc, which the analyser does not follow.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Scale', Justification = 'Read inside the Regex.Replace script block that runs mmdc, which the analyser does not follow.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Root,
        [ValidateSet('png', 'svg')] [string] $Format = 'png',
        [string] $AssetsDir = 'assets',
        [string] $Theme = 'default',
        [string] $Background = 'white',
        [int] $Width = 1400,
        [int] $Scale = 2
    )

    Set-StrictMode -Off
    $ErrorActionPreference = 'Stop'

    if (-not (Test-Path $Root)) { throw "Root not found: $Root" }

    if (-not (Get-Command 'mmdc' -ErrorAction SilentlyContinue)) {
        throw 'mmdc not found on PATH. Install via: npm install -g @mermaid-js/mermaid-cli'
    }

    # Puppeteer launch config, Linux hosted CI agents run as root and need
    # --no-sandbox. Harmless on macOS/Windows.
    $puppeteerCfg = Join-Path ([System.IO.Path]::GetTempPath()) 'puppeteer-mmdc.json'
    '{ "args": ["--no-sandbox", "--disable-setuid-sandbox"] }' | Set-Content -Path $puppeteerCfg -Encoding UTF8

    $workspaceDirs = Get-ChildItem -Path $Root -Directory -ErrorAction SilentlyContinue
    if (-not $workspaceDirs) {
        Write-Host "No workspace folders found under $Root, nothing to do."
        return
    }

    $count = @{ Seen = 0; Rewritten = 0; Failed = 0 }

    foreach ($wsDir in $workspaceDirs) {
        $assetsPath = Join-Path $wsDir.FullName $AssetsDir
        New-Item -ItemType Directory -Path $assetsPath -Force | Out-Null

        $mdFiles = Get-ChildItem -Path $wsDir.FullName -Filter '*.md' -File
        foreach ($md in $mdFiles) {
            $content = Get-Content -Path $md.FullName -Raw
            if ($content -notmatch '```mermaid') { continue }

            $rx = [regex]'(?ms)```mermaid\s*\r?\n(.*?)\r?\n```'
            $matchCount = $rx.Matches($content).Count
            $count.Seen += $matchCount

            $newContent = $rx.Replace($content, {
                    param($m)
                    $body = $m.Groups[1].Value.TrimEnd()
                    $hash = Get-MermaidHash $body
                    $imgPath = Join-Path $assetsPath "$hash.$Format"
                    if (-not (Test-Path $imgPath)) {
                        $temp = Join-Path ([System.IO.Path]::GetTempPath()) "mmd-$hash.mmd"
                        Set-Content -Path $temp -Value $body -Encoding UTF8 -NoNewline
                        try {
                            $mmdcArgs = @(
                                '-i', $temp
                                '-o', $imgPath
                                '-t', $Theme
                                '-b', $Background
                                '-w', $Width
                                '-p', $puppeteerCfg
                            )
                            # -s (scale) only affects raster output.
                            if ($Format -eq 'png') { $mmdcArgs += @('-s', $Scale) }
                            & mmdc @mmdcArgs 2>&1 | Out-Null
                        } finally {
                            Remove-Item $temp -Force -ErrorAction SilentlyContinue
                        }
                        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $imgPath)) {
                            Write-Warning "mmdc failed for hash $hash, leaving fence in place"
                            $count.Failed++
                            return $m.Value
                        }
                    }
                    $count.Rewritten++
                    return "![Diagram]($AssetsDir/$hash.$Format)"
                })

            if ($newContent -ne $content) {
                Set-Content -Path $md.FullName -Value $newContent -Encoding UTF8
                Write-Host "  ↳ rewrote $($wsDir.Name)/$($md.Name), $matchCount charts"
            }
        }
    }

    Write-Host ''
    Write-Host '##[section]Mermaid pre-render summary'
    Write-Host "  Format          : $Format"
    Write-Host "  Charts seen     : $($count.Seen)"
    Write-Host "  Images emitted  : $($count.Rewritten)"
    Write-Host "  Failures        : $($count.Failed)"
    Write-Host "  Assets root     : <workspace>/$AssetsDir/"
}

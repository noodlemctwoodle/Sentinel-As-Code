#requires -Version 7
<#
.SYNOPSIS
    Pre-renders Mermaid fenced blocks in the Documenter's markdown output to
    standalone SVG files and rewrites the blocks as image references.

.DESCRIPTION
    ADO Repos' markdown preview and ADO's "publish code as wiki" both
    render Mermaid fences as plain code, not as diagrams. ADO Wiki proper
    renders them, but its bundled Mermaid version lags the latest release
    and the experimental chart types we emit (xychart-beta, sankey-beta)
    are silently dropped.

    This script bridges that gap. After the renderer produces
    SecurityDocs/<workspace>/*.md, this pass walks every markdown file,
    extracts each fenced ```mermaid block, runs it through
    `@mermaid-js/mermaid-cli` (mmdc), and rewrites the fenced block as
    `![Diagram](assets/<hash>.svg)`. The result renders identically on
    every Markdown host — Repos preview, code-wiki, GitHub, MkDocs.

    The SVG filename is the first 12 chars of the SHA-256 hash of the
    Mermaid body, so identical diagrams across files share an SVG and
    re-runs are idempotent (already-rendered hashes are reused).

    mmdc failures are warnings — the offending fenced block is left as-is
    so a syntax error on one chart never breaks the whole doc set.

.PARAMETER Root
    Root directory containing per-workspace folders (e.g. SecurityDocs/).
    Each subfolder is treated as an isolated docset with its own
    assets/<hash>.svg sidecar directory.

.PARAMETER AssetsDir
    Name of the per-workspace asset folder. Defaults to 'assets'.

.PARAMETER Theme
    mmdc theme. 'dark' / 'forest' / 'neutral' / 'default'. Defaults to 'dark'.

.PARAMETER Background
    mmdc background. 'transparent' / '#ffffff' / colour name. Defaults to
    'transparent' so the SVG inherits the host's page colour (good for
    both light and dark wiki themes).

.PARAMETER Width
    mmdc render width in pixels. Defaults to 1400 to match the wider charts
    we already emit (MITRE, XDR bar).

.EXAMPLE
    pwsh ./Convert-MermaidToSvg.ps1 -Root ./SecurityDocs

.NOTES
    Requires Node.js and @mermaid-js/mermaid-cli installed globally:
        npm install -g @mermaid-js/mermaid-cli
    On Linux CI agents the script writes a puppeteer config enabling
    --no-sandbox automatically.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Root,
    [string]$AssetsDir  = 'assets',
    [string]$Theme      = 'dark',
    [string]$Background = 'transparent',
    [int]   $Width      = 1400
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $Root)) { throw "Root not found: $Root" }

$mmdcCmd = Get-Command 'mmdc' -ErrorAction SilentlyContinue
if (-not $mmdcCmd) {
    throw "mmdc not found on PATH. Install via: npm install -g @mermaid-js/mermaid-cli"
}

# Puppeteer launch config — Linux hosted CI agents run as root and need
# --no-sandbox. Harmless on macOS/Windows.
$puppeteerCfg = Join-Path ([System.IO.Path]::GetTempPath()) 'puppeteer-mmdc.json'
@'
{ "args": ["--no-sandbox", "--disable-setuid-sandbox"] }
'@ | Set-Content -Path $puppeteerCfg -Encoding UTF8

function Get-MermaidHash {
    param([string]$Text)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $sha   = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hex = [System.BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', ''
    } finally { $sha.Dispose() }
    return $hex.Substring(0, 12).ToLower()
}

$workspaceDirs = Get-ChildItem -Path $Root -Directory -ErrorAction SilentlyContinue
if (-not $workspaceDirs) {
    Write-Host "No workspace folders found under $Root — nothing to do."
    return
}

$totalCharts = 0
$totalRewritten = 0
$totalFailed = 0

foreach ($wsDir in $workspaceDirs) {
    $assetsPath = Join-Path $wsDir.FullName $AssetsDir
    New-Item -ItemType Directory -Path $assetsPath -Force | Out-Null

    $mdFiles = Get-ChildItem -Path $wsDir.FullName -Filter '*.md' -File
    foreach ($md in $mdFiles) {
        $content = Get-Content -Path $md.FullName -Raw
        if ($content -notmatch '```mermaid') { continue }

        $rx = [regex]'(?ms)```mermaid\s*\r?\n(.*?)\r?\n```'
        $matchCount = $rx.Matches($content).Count
        $totalCharts += $matchCount

        $newContent = $rx.Replace($content, {
            param($m)
            $body = $m.Groups[1].Value.TrimEnd()
            $hash = Get-MermaidHash $body
            $svgPath = Join-Path $assetsPath "$hash.svg"
            if (-not (Test-Path $svgPath)) {
                $temp = Join-Path ([System.IO.Path]::GetTempPath()) "mmd-$hash.mmd"
                Set-Content -Path $temp -Value $body -Encoding UTF8 -NoNewline
                try {
                    & mmdc `
                        -i $temp `
                        -o $svgPath `
                        -t $Theme `
                        -b $Background `
                        -w $Width `
                        -p $puppeteerCfg `
                        2>&1 | Out-Null
                } finally {
                    Remove-Item $temp -Force -ErrorAction SilentlyContinue
                }
                if ($LASTEXITCODE -ne 0 -or -not (Test-Path $svgPath)) {
                    Write-Warning "mmdc failed for hash $hash — leaving fence in place"
                    $script:totalFailed++
                    return $m.Value
                }
            }
            $script:totalRewritten++
            return "![Diagram]($AssetsDir/$hash.svg)"
        })

        if ($newContent -ne $content) {
            Set-Content -Path $md.FullName -Value $newContent -Encoding UTF8
            Write-Host "  ↳ rewrote $($wsDir.Name)/$($md.Name) — $matchCount charts"
        }
    }
}

Write-Host ""
Write-Host "##[section]Mermaid pre-render summary"
Write-Host "  Charts seen     : $totalCharts"
Write-Host "  SVGs emitted    : $totalRewritten"
Write-Host "  Failures        : $totalFailed"
Write-Host "  Assets root     : <workspace>/$AssetsDir/"

#Requires -Version 7.2

<#
.SYNOPSIS
    Bundle the chart web part's renderers for the SharePoint dashboard.

.DESCRIPTION
    The chart web part draws every chart kind the section model carries
    (pie, xy, sankey, timeline, gantt, mindmap, flowchart, state, class,
    sequence, journey) from TypeScript under
    src/webparts/isocBlueprintChart/charts. The dashboard's Report tab uses
    the same renderers, so a diagram looks the same on a SharePoint page
    and in the dashboard and has one implementation.

    This script compiles those files with TypeScript (CommonJS modules),
    wraps each in a small module loader and writes one self-contained
    script, Engine/SharePoint/templates/dashboard-charts.js, which exposes
    window.SacCharts (renderChart, setTextMeasurer, FONT). The site build
    puts it into the dashboard page in place of /*__SAC_CHARTS__*/.

    The bundle records the SHA-256 of its sources; a Pester test fails when
    a chart source changes without the bundle being regenerated. The hash
    is taken over the .ts files in ordinal name order, each as its name, a
    line feed, its content with line feeds only, and a line feed.

    Run it after changing any file under charts/:

        ./Modules/iSOCBlueprint/WebParts/Build-DashboardCharts.ps1

    It needs Node.js and TypeScript: npm ci in this folder installs the
    version the web part pins, or pass -TscPath.

.PARAMETER TscPath
    The TypeScript compiler to use. Defaults to node_modules/.bin/tsc in
    this folder, then tsc on the PATH.

.PARAMETER OutFile
    Where to write the bundle. Defaults to the dashboard template folder.

.EXAMPLE
    ./Modules/iSOCBlueprint/WebParts/Build-DashboardCharts.ps1

.NOTES
    File:         Modules/iSOCBlueprint/WebParts/Build-DashboardCharts.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-14
    Version:      0.1.0
    Last Updated: 2026-10-14
    Requires:     PowerShell 7.2+, Node.js, TypeScript 5.3
#>
[CmdletBinding()]
param(
    [string] $TscPath,
    [string] $OutFile = (Join-Path $PSScriptRoot '../Engine/SharePoint/templates/dashboard-charts.js')
)

$ErrorActionPreference = 'Stop'
$chartsDir = Join-Path $PSScriptRoot 'src/webparts/isocBlueprintChart/charts'
# Ordinal order, so the hash does not depend on the machine's culture.
function Get-OrdinalSorted([System.IO.FileInfo[]] $Files) {
    $names = [string[]]@($Files | ForEach-Object Name)
    [Array]::Sort($names, [StringComparer]::Ordinal)
    foreach ($n in $names) { $Files | Where-Object Name -CEQ $n }
}
$sources = @(Get-OrdinalSorted @(Get-ChildItem -LiteralPath $chartsDir -Filter '*.ts' -File))
if (-not $sources.Count) { throw "No chart sources under $chartsDir." }

# The hash of the sources, as the Pester drift test recomputes it.
$sb = [System.Text.StringBuilder]::new()
foreach ($f in $sources) {
    $text = (Get-Content -LiteralPath $f.FullName -Raw -Encoding utf8) -replace "`r`n", "`n"
    [void]$sb.Append($f.Name).Append("`n").Append($text).Append("`n")
}
$sha = [System.Security.Cryptography.SHA256]::Create()
$sourceHash = ([System.BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($sb.ToString())))).Replace('-', '').ToLowerInvariant()

if (-not $TscPath) {
    $local = Join-Path $PSScriptRoot 'node_modules/.bin/tsc'
    $TscPath = if (Test-Path -LiteralPath $local) { $local } else { (Get-Command tsc -ErrorAction SilentlyContinue).Source }
}
if (-not $TscPath -or -not (Test-Path -LiteralPath $TscPath)) {
    throw 'TypeScript not found: run npm ci in Modules/iSOCBlueprint/WebParts, or pass -TscPath.'
}

$work = Join-Path ([System.IO.Path]::GetTempPath()) "sac-charts-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $work -Force | Out-Null
try {
    & $TscPath --module commonjs --target es2017 --lib es2017,dom --moduleResolution node --skipLibCheck --strict --outDir $work @($sources.FullName)
    if ($LASTEXITCODE -ne 0) { throw "TypeScript failed (exit $LASTEXITCODE)." }

    $modules = @(Get-OrdinalSorted @(Get-ChildItem -LiteralPath $work -Filter '*.js' -File))
    $nl = "`n"
    $out = [System.Text.StringBuilder]::new()
    [void]$out.Append("/* dashboard-charts.js: the chart web part's renderers (Modules/iSOCBlueprint/WebParts/src/webparts/isocBlueprintChart/charts)$nl")
    [void]$out.Append("   bundled for the SharePoint dashboard by Modules/iSOCBlueprint/WebParts/Build-DashboardCharts.ps1. Do not edit;$nl")
    [void]$out.Append("   regenerate after changing the chart sources.$nl")
    [void]$out.Append("   sources-sha256: $sourceHash */$nl")
    [void]$out.Append("(function(){$nl'use strict';$nl var defs={};$nl")
    foreach ($m in $modules) {
        $name = [System.IO.Path]::GetFileNameWithoutExtension($m.Name)
        $code = (Get-Content -LiteralPath $m.FullName -Raw -Encoding utf8) -replace "`r`n", "`n"
        [void]$out.Append(" defs['$name']=function(module,exports,require){$nl$code$nl};$nl")
    }
    [void]$out.Append(" var cache={};$nl function req(n){ n=n.replace(/^\.\//,'').replace(/\.js$/,''); if(cache[n]) return cache[n].exports; if(!defs[n]) throw new Error('No chart module '+n); var m={exports:{}}; cache[n]=m; defs[n](m,m.exports,req); return m.exports; }$nl")
    [void]$out.Append(" var kit=req('ChartKit'), rc=req('renderChart');$nl")
    [void]$out.Append(" window.SacCharts={ renderChart: rc.renderChart, setTextMeasurer: kit.setTextMeasurer, FONT: kit.FONT };$nl")
    [void]$out.Append("})();$nl")
    $bundle = $out.ToString()
    # The bundle goes inside a script element, which a closing tag would end.
    if ($bundle -match '(?i)</script') { throw 'The bundle contains </script; it cannot be inlined.' }
    Set-Content -LiteralPath $OutFile -Value $bundle -Encoding utf8 -NoNewline
    Write-Information "Wrote $OutFile ($($modules.Count) modules, sources $sourceHash)." -InformationAction Continue
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

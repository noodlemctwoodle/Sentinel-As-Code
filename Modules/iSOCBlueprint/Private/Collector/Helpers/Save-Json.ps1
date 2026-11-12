#Requires -Version 7.6

<#
.SYNOPSIS
    Write one capture to _raw as JSON.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Helpers/Save-Json.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, Collector
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function Save-Json {
    # $Data is intentionally optional + nullable. An ARM endpoint that returns no
    # results legitimately surfaces as $null in PowerShell, the helper should
    # write '[]' for that case rather than refusing the parameter, otherwise the
    # collector emits dozens of misleading 'Cannot bind argument to parameter
    # Data because it is null' warnings on a quiet workspace.
    #
    # -AsArray on every save protects against PowerShells unwrap-single-element
    # quirk where a one-item array is serialized as a single object, which then
    # breaks downstream array-shaped readers (Read-RawArray + ForEach-Object).
    param(
        [Parameter(Mandatory)] [string]$FileName,
        [Parameter(Mandatory = $false)] [AllowNull()] $Data
    )
    $target = Join-Path $script:RawOut $FileName
    $singleObjectFiles = @(
        'workspace.json','run-context.json','settings.json','cost-estimate.json',
        'subscription.json','dedicated-cluster.json','maturity.json','bookmarks-count.json',
        'whats-new.json'
    )
    if ($null -eq $Data) {
        if ($singleObjectFiles -contains $FileName) {
            '{}' | Set-Content -Path $target -Encoding UTF8
        } else {
            '[]' | Set-Content -Path $target -Encoding UTF8
        }
    }
    elseif ($singleObjectFiles -contains $FileName) {
        $Data | ConvertTo-Json -Depth 32 -EnumsAsStrings | Set-Content -Path $target -Encoding UTF8
    }
    else {
        # Collection-shape file. Pipe through ConvertTo-Json so each item is
        # treated as a separate input, pipe + -AsArray always emits a JSON
        # array, including the single-element and empty cases. Using
        # -InputObject would treat the whole array as one input, which then
        # double-wraps under -AsArray.
        $items = @($Data)
        if ($items.Count -eq 0) {
            '[]' | Set-Content -Path $target -Encoding UTF8
        } else {
            $items | ConvertTo-Json -Depth 32 -EnumsAsStrings -AsArray | Set-Content -Path $target -Encoding UTF8
        }
    }
    Write-Information "  ↳ wrote $FileName"
}

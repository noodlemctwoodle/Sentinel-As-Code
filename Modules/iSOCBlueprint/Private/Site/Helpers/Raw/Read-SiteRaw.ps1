#Requires -Version 7.6

<#
.SYNOPSIS
    Read one _raw JSON file as an object, or null when absent.

.DESCRIPTION
    Helper for the SharePoint site build (Invoke-iSOCBlueprintSiteBuild).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Site/Helpers/Raw/Read-SiteRaw.ps1
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

function Read-SiteRaw {
    <#
    .SYNOPSIS
        Read one _raw/<name> JSON file into an object, or $null if absent,
        empty or unparseable.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Name)

    $path = Join-Path $script:RawRoot $Name
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try {
        $text = Get-Content -LiteralPath $path -Raw -Encoding utf8
        if ([string]::IsNullOrWhiteSpace($text)) { return $null }
        $obj = $text | ConvertFrom-Json -Depth 64
        # Snapshots collected before the Documenter was renamed Blueprint carry
        # DocumenterVersion; read it as BlueprintVersion.
        if ($Name -eq 'run-context.json' -and $obj -and -not $obj.PSObject.Properties['BlueprintVersion'] -and $obj.PSObject.Properties['DocumenterVersion']) {
            $obj | Add-Member -NotePropertyName BlueprintVersion -NotePropertyValue $obj.DocumenterVersion
        }
        return $obj
    }
    catch {
        Write-SiteLog "  ! could not parse _raw/$Name : $($_.Exception.Message)" Warning
        return $null
    }
}

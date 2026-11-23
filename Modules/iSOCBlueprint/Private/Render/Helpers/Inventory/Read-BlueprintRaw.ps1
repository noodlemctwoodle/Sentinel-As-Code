#Requires -Version 7.6

<#
.SYNOPSIS
    Read one JSON file from _raw/ as an object.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Helpers/Inventory/Read-BlueprintRaw.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Read-BlueprintRaw {
    <#
    .SYNOPSIS
        Read one JSON file from _raw/ as an object.

    .DESCRIPTION
        Returns $null when the file is missing or blank. Snapshots collected before
        the Documenter was renamed Blueprint carry DocumenterVersion in
        run-context.json; it is read as BlueprintVersion.

    .PARAMETER Name
        The file name under $script:RawRoot.

    .OUTPUTS
        The parsed JSON, or $null.
    #>
    [CmdletBinding()]
    param([string]$Name)
    $p = Join-Path $script:RawRoot $Name
    if (-not (Test-Path $p)) { return $null }
    $raw = Get-Content $p -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    $obj = $raw | ConvertFrom-Json -Depth 32
    # Snapshots collected before the Documenter was renamed Blueprint carry
    # DocumenterVersion; read it as BlueprintVersion.
    if ($Name -eq 'run-context.json' -and $obj -and -not $obj.PSObject.Properties['BlueprintVersion'] -and $obj.PSObject.Properties['DocumenterVersion']) {
        $obj | Add-Member -NotePropertyName BlueprintVersion -NotePropertyValue $obj.DocumenterVersion
    }
    return $obj
}

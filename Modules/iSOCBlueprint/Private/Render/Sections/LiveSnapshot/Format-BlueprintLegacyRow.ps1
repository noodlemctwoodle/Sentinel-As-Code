#Requires -Version 7.6

<#
.SYNOPSIS
    Build one row of the legacy-features table.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/LiveSnapshot/Format-BlueprintLegacyRow.ps1
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

function Format-BlueprintLegacyRow {
    <#
    .SYNOPSIS
        Build one row of the legacy-features table.

    .DESCRIPTION
        Legacy and deprecated features still in use, one row each, read from the
        same captures their pages use. A capture missing from an older snapshot
        shows as Not captured rather than as not in use. Status is 'Not captured'
        when the capture is missing, 'In use' when Count is above zero and 'Not in
        use' otherwise. The evidence is left blank when the capture is missing.

    .PARAMETER Feature
        The feature name.

    .PARAMETER Count
        How many instances were found.

    .PARAMETER Captured
        True when the data for this check was captured in the snapshot.

    .PARAMETER Evidence
        The evidence text, kept only when the capture exists.

    .PARAMETER Where
        Where to read more, as Markdown links.

    .OUTPUTS
        [pscustomobject] with Feature, Status, Evidence and Where.
    #>
    [CmdletBinding()]
    param([string]$Feature, $Count, [bool]$Captured, [string]$Evidence, [string]$Where)
    [pscustomobject]@{
        Feature  = $Feature
        Status   = $(if (-not $Captured) { 'Not captured' } elseif ([double]$Count -gt 0) { 'In use' } else { 'Not in use' })
        Evidence = $(if ($Captured) { $Evidence } else { '' })
        Where    = $Where
    }
}

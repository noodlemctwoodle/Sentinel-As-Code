#Requires -Version 7.6

<#
.SYNOPSIS
    Join MITRE tactic names for display.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Helpers/Formatting/Format-TacticList.ps1
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

function Format-TacticList {
    <#
    .SYNOPSIS
        Join MITRE tactic names for display.

    .PARAMETER Tactics
        The tactic names. Empty entries are skipped; each is shown through
        Format-TacticName.

    .PARAMETER Separator
        The text placed between names. Defaults to a comma and a space.

    .OUTPUTS
        [string].
    #>
    [CmdletBinding()]
    param($Tactics, [string]$Separator = ', ')
    return (@($Tactics | Where-Object { $_ } | ForEach-Object { Format-TacticName ([string]$_) }) -join $Separator)
}

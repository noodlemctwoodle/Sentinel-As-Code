#Requires -Version 7.6

<#
.SYNOPSIS
    Escape text that would otherwise start a Markdown list item.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/GapAnalysis/ConvertTo-BlueprintListItem.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

# Evidence + Learn link formatters for the detailed remediation cards
# below. Evidence text from gap rules can be very long with semicolon-
# separated lists (e.g. 657 disabled rule names). Cramming that into a
# narrow table cell is unreadable. The detail-card form splits long
# semicolon lists into bullet items and renders short evidence inline.
# A list item that starts with a Markdown block marker (a rule named
# "* Detection ..." or "1. Test") would open a nested list, a heading or a
# quote and leave its own bullet empty; a backslash keeps it as text.
function ConvertTo-BlueprintListItem {
    param([string]$Text)
    return (($Text -replace '^([*+\-#>])(?=\s|$)', '\$1') -replace '^(\d+)([.)])(?=\s|$)', '$1\$2')
}

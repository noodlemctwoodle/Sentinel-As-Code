#Requires -Version 7.6

<#
.SYNOPSIS
    Test whether a table column holds identifiers rather than counts.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Helpers/Formatting/Test-IdentifierColumn.ps1
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

# A column holding an identifier or a code (Event ID, Port, Version, Year),
# not a quantity: its numbers are printed as they are, so 4624 is never
# 4,624 and 1.5 never 1.50. Judged on the header's last word.
function Test-IdentifierColumn([string]$Name) {
    $last = @((Format-ColumnLabel $Name) -split '[\s_-]+')[-1]
    return $last -in 'id', 'ids', 'port', 'ports', 'version', 'year', 'code', 'level', 'pid'
}

#Requires -Version 7.6

<#
.SYNOPSIS
    Turn a column name into its table header text.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Helpers/Formatting/Format-ColumnLabel.ps1
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

function Format-ColumnLabel {
    <#
    .SYNOPSIS
        Turn a column name into its table header text.

    .DESCRIPTION
        A name listed in $script:ColumnLabels is replaced by its label. Any other
        name made of letters and digits that runs words together in camel case is
        split into words: the first keeps its case and the rest are lower-cased,
        except runs of capitals such as GB. Any other name comes back unchanged.

    .PARAMETER Name
        The column (property) name.

    .OUTPUTS
        [string].
    #>
    [CmdletBinding()]
    param([string]$Name)
    if ($script:ColumnLabels.ContainsKey($Name)) { return $script:ColumnLabels[$Name] }
    if ($Name -cnotmatch '^[A-Za-z][A-Za-z0-9]*$' -or $Name -cnotmatch '[a-z][A-Z]|[A-Z]{2}[a-z]') { return $Name }
    $words = @([regex]::Split($Name, '(?<=[a-z0-9])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])'))
    $rest = @($words | Select-Object -Skip 1 | ForEach-Object { if ($_ -cmatch '^[A-Z]{2,}$') { $_ } else { $_.ToLowerInvariant() } })
    return (@($words[0]) + $rest) -join ' '
}

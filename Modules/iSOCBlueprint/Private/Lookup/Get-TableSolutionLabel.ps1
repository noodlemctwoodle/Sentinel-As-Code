#Requires -Version 7.6

<#
.SYNOPSIS
    Name the Content Hub solutions that ship a table, marking the ones installed on the workspace

.DESCRIPTION
    Split from Get-ConnectorCatalogue.ps1 so each file holds one function.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Lookup/Get-TableSolutionLabel.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-13
    Version:      0.1.0
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-TableSolutionLabel {
    <#
    .SYNOPSIS
        Name the Content Hub solutions that ship a table, marking the ones
        installed on the workspace.

    .PARAMETER Catalogue
        The output of Import-ConnectorCatalogue.

    .PARAMETER Table
        A table name.

    .PARAMETER InstalledSolutions
        Display names of the installed Content Hub solutions.

    .OUTPUTS
        [string] The solutions, '(installed)' after each one installed, when
        at most three ship the table; otherwise how many share it and which
        of them are installed. '' when the catalogue does not know the table.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] $Catalogue,
        [Parameter(Mandatory)] [string] $Table,
        [AllowEmptyCollection()] [string[]] $InstalledSolutions = @()
    )

    if (-not $Catalogue.ByTable.ContainsKey($Table)) { return '' }
    $solutions = @(@($Catalogue.ByTable[$Table]) | ForEach-Object { [string]$_.solution } | Where-Object { $_ -and $_ -ne 'Platform' } | Sort-Object -Unique)
    if ($solutions.Count -eq 0) { return '' }
    $installed = @(
        $solutions | Where-Object { $s = $_; @($InstalledSolutions | Where-Object { $_ -and $_.Equals($s, [StringComparison]::OrdinalIgnoreCase) }).Count }
    )
    if ($solutions.Count -le 3) {
        return (@($solutions | ForEach-Object { if ($installed -contains $_) { "$_ (installed)" } else { $_ } }) -join '; ')
    }
    $tail = if ($installed.Count) { '; installed: ' + ($installed -join '; ') } else { '' }
    return "Shared by $($solutions.Count) solutions$tail"
}

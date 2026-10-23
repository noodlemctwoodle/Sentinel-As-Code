#Requires -Version 7.2

<#
.SYNOPSIS
    Read the iSOCBlueprint migration map for the migration suite.

.DESCRIPTION
    Modules/iSOCBlueprint/MIGRATION.md records where every file under the
    old Tools/Blueprint folder went when the Blueprint became the
    iSOCBlueprint module. Get-MigrationMap parses its table so the
    migration suite can check the move stays complete.

.NOTES
    File:         Tests/iSOCBlueprint/_helpers/Migration.psm1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-13
    Version:      0.2.0
    Last Updated: 2026-10-13
    Requires:     PowerShell 7.2+

    Version 0.1.0 also computed the text each engine copy had to have while
    Tools/Blueprint and the engine existed side by side; that went with the
    old folder.

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Keeps the file help above from being read as the help of the function below.

function Get-MigrationMap {
    <#
    .SYNOPSIS
        Parse the table in Modules/iSOCBlueprint/MIGRATION.md.

    .PARAMETER RepoRoot
        Repository root.

    .OUTPUTS
        One [pscustomobject] per row: Source, Action, Destination, Edits
        (string[]), Notes. Paths are repository-relative, backticks removed.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)] [string] $RepoRoot)

    $path = Join-Path $RepoRoot 'Modules/iSOCBlueprint/MIGRATION.md'
    foreach ($line in Get-Content -LiteralPath $path) {
        if ($line -notmatch '^\|\s*`') { continue }
        $cells = @($line.Trim().Trim('|').Split('|') | ForEach-Object { $_.Trim().Trim('`') })
        if ($cells.Count -ne 5) { throw "MIGRATION.md row does not have five cells: $line" }
        [pscustomobject]@{
            Source      = $cells[0]
            Action      = $cells[1]
            Destination = $cells[2]
            Edits       = @($cells[3] -split '\s*,\s*' | Where-Object { $_ })
            Notes       = $cells[4]
        }
    }
}

Export-ModuleMember -Function Get-MigrationMap

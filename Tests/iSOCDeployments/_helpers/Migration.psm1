#Requires -Version 7.2

<#
.SYNOPSIS
    Read the iSOCDeployments migration map for the migration suite.

.DESCRIPTION
    Modules/iSOCDeployments/MIGRATION.md records where every script and
    function the module replaces goes, and the edits made on the way.
    Get-iSOCDeploymentsMigrationMap parses its three tables so
    Tests/iSOCDeployments/Migration-Map.Tests.ps1 can check them against
    the repository.

.NOTES
    File:         Tests/iSOCDeployments/_helpers/Migration.psm1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-23
    Version:      0.1.0
    Last Updated: 2026-10-23
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCDeploymentsMigrationMap {
    <#
    .SYNOPSIS
        Parse the Scripts, Functions and Edits tables in MIGRATION.md.

    .PARAMETER RepoRoot
        Repository root.

    .OUTPUTS
        [pscustomobject] Scripts (Source, ReplacedBy, Status), Functions
        (Source, Function, Destination, Edits, Notes) and Edits (Id, Change,
        Why). Paths are repository-relative, backticks removed.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)] [string] $RepoRoot)

    $path = Join-Path $RepoRoot 'Modules/iSOCDeployments/MIGRATION.md'
    $section = $null
    $scripts = [System.Collections.Generic.List[object]]::new()
    $functions = [System.Collections.Generic.List[object]]::new()
    $edits = [System.Collections.Generic.List[object]]::new()

    foreach ($line in Get-Content -LiteralPath $path) {
        if ($line -match '^## (.+)$') { $section = $Matches[1].Trim(); continue }
        if ($line -notmatch '^\|' -or $line -match '^\|\s*-' -or $line -match '^\|\s*(Source|ID)\s*\|') { continue }
        $cells = @($line.Trim().Trim('|').Split('|') | ForEach-Object { $_.Trim() })
        $plain = @($cells | ForEach-Object { $_.Trim('`') })
        switch ($section) {
            'Scripts' {
                if ($cells.Count -ne 3) { throw "MIGRATION.md Scripts row does not have three cells: $line" }
                $scripts.Add([pscustomobject]@{ Source = $plain[0]; ReplacedBy = $cells[1]; Status = $plain[2] })
            }
            'Functions' {
                if ($cells.Count -ne 5) { throw "MIGRATION.md Functions row does not have five cells: $line" }
                $functions.Add([pscustomobject]@{
                        Source      = $plain[0]
                        Function    = $plain[1]
                        Destination = $plain[2]
                        Edits       = @($plain[3] -split '\s*,\s*' | Where-Object { $_ -and $_ -ne '-' })
                        Notes       = $cells[4]
                    })
            }
            'Edits' {
                if ($cells.Count -ne 3) { throw "MIGRATION.md Edits row does not have three cells: $line" }
                $edits.Add([pscustomobject]@{ Id = $plain[0]; Change = $cells[1]; Why = $cells[2] })
            }
        }
    }

    [pscustomobject]@{
        Scripts   = $scripts.ToArray()
        Functions = $functions.ToArray()
        Edits     = $edits.ToArray()
    }
}

Export-ModuleMember -Function Get-iSOCDeploymentsMigrationMap

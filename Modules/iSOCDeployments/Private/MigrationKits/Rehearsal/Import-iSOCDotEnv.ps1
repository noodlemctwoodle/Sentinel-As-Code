#Requires -Version 7.6

<#
.SYNOPSIS
    Read a dotenv file's KEY=VALUE lines.

.DESCRIPTION
    Blank lines and comments are skipped, an export prefix and one layer of
    quotes are taken off; a missing file is no settings.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/Rehearsal/Import-iSOCDotEnv.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Import-iSOCDotEnv {
    <#
    .SYNOPSIS
        Read a dotenv file's KEY=VALUE lines.

    .DESCRIPTION
        Blank lines and lines starting # are skipped; an export prefix is
        allowed, and one layer of single or double quotes round a value is
        taken off. A file that does not exist is no settings. Nothing is
        written to the environment.

    .PARAMETER Path
        The file.

    .OUTPUTS
        [hashtable]

    .EXAMPLE
        Import-iSOCDotEnv -Path ./.env
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    $result = @{}
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $result }

    foreach ($line in Get-Content -LiteralPath $Path) {
        $trimmed = $line.Trim()
        if ($trimmed.Length -eq 0 -or $trimmed.StartsWith('#')) { continue }
        if ($trimmed -match '^(?:export\s+)?(?<k>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*(?<v>.*)$') {
            $key = $Matches['k']
            $value = $Matches['v'].Trim()
            if ($value.Length -ge 2 -and (($value[0] -eq '"' -and $value[-1] -eq '"') -or ($value[0] -eq "'" -and $value[-1] -eq "'"))) {
                $value = $value.Substring(1, $value.Length - 2)
            }
            $result[$key] = $value
        }
    }
    $result
}

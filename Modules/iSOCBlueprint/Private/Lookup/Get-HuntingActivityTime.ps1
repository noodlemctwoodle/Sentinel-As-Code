#Requires -Version 7.6

<#
.SYNOPSIS
    Get-HuntingActivityTime, a helper of Get-HuntingActivity.

.DESCRIPTION
    One of the helpers beside Get-HuntingActivity.ps1, which describes the whole.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Lookup/Get-HuntingActivityTime.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-15
    Version:      0.1.0
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-HuntingActivityTime {
    <#
    .SYNOPSIS
        The latest of the named date properties on an object (UTC), or
        $null when it has none that parse.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()] $Object,
        [string[]] $Names
    )
    if ($null -eq $Object) { return $null }
    $latest = $null
    foreach ($n in $Names) {
        $p = $Object.PSObject.Properties[$n]
        if (-not $p -or -not $p.Value) { continue }
        $t = [datetime]::MinValue
        if ($p.Value -is [datetime]) { $t = $p.Value.ToUniversalTime() }
        elseif (-not [datetime]::TryParse([string]$p.Value, [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$t)) {
            continue
        }
        if ($null -eq $latest -or $t -gt $latest) { $latest = $t }
    }
    $latest
}

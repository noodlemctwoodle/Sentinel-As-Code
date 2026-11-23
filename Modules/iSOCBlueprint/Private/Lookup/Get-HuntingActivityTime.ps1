#Requires -Version 7.6

<#
.SYNOPSIS
    The latest of the named date properties on an object, in UTC.

.DESCRIPTION
    One of the helpers beside Get-HuntingActivity.ps1, which describes the whole.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Lookup/Get-HuntingActivityTime.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-15
    Version:      0.1.1
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-HuntingActivityTime {
    <#
    .SYNOPSIS
        The latest of the named date properties on an object (UTC), or $null
        when it has none that parse.

    .DESCRIPTION
        A property that is a datetime is converted to UTC; any other value is
        parsed with the invariant culture and read as UTC. A property that is
        absent, empty or not a date is skipped.

    .PARAMETER Object
        The object to read. Null gives $null.

    .PARAMETER Names
        The names of the date properties to read.

    .OUTPUTS
        [datetime] The latest time, in UTC, or $null.
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

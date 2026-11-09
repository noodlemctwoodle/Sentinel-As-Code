#Requires -Version 7.6

<#
.SYNOPSIS
    Read a value at a dotted path without tripping strict mode.

.NOTES
    File:         Modules/iSOCDeployments/Private/Core/Get-iSOCPropertyValue.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-23
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCPropertyValue {
    <#
    .SYNOPSIS
        Follow a path such as properties.displayName through dictionaries and
        objects.

    .DESCRIPTION
        The module runs in strict mode, where reading a property an API
        response does not have throws. This walks the path one segment at a
        time through dictionaries (a YAML file) and objects (an API
        response) alike, and returns nothing as soon as a segment is
        missing.

    .PARAMETER InputObject
        The value to read from.

    .PARAMETER Path
        Segments separated by dots.

    .OUTPUTS
        The value, or nothing.

    .EXAMPLE
        Get-iSOCPropertyValue -InputObject $workspace -Path 'properties.customerId'
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [AllowNull()]
        [object] $InputObject,

        [Parameter(Mandatory)]
        [string] $Path
    )

    $current = $InputObject
    foreach ($segment in $Path.Split('.')) {
        if ($null -eq $current) { return }
        if ($current -is [System.Collections.IDictionary]) {
            if (-not $current.Contains($segment)) { return }
            $current = $current[$segment]
            continue
        }
        $property = $current.PSObject.Properties[$segment]
        if (-not $property) { return }
        $current = $property.Value
    }
    , $current
}

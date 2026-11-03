#Requires -Version 7.2

<#
.SYNOPSIS
    Serialise a value with every key in a fixed order.

.NOTES
    File:         Modules/iSOCDeployments/Private/Drift/ConvertTo-iSOCCanonicalJson.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-23
    Version:      0.1.0
    Last Updated: 2026-10-23
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function ConvertTo-iSOCCanonicalJson {
    <#
    .SYNOPSIS
        Compressed JSON with dictionary keys and object properties sorted.

    .DESCRIPTION
        A hashtable read from YAML and an object read from an API response
        hold the same value with their keys in different orders. Sorting
        every key (ordinal) at every depth gives one text per value, so two
        values are equal when their canonical JSON is. Lists keep their
        order.

    .PARAMETER InputObject
        The value: dictionaries, objects, lists and scalars, nested.

    .OUTPUTS
        [string]

    .EXAMPLE
        (ConvertTo-iSOCCanonicalJson $repo) -ceq (ConvertTo-iSOCCanonicalJson $workspace)
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Position = 0)]
        [AllowNull()]
        [object] $InputObject
    )

    $sort = {
        param($Value)
        if ($null -eq $Value) { return $null }
        if ($Value -is [string] -or $Value -is [System.ValueType]) { return $Value }
        if ($Value -is [System.Collections.IDictionary]) {
            $keys = [string[]]@($Value.Keys | ForEach-Object { [string]$_ })
            [Array]::Sort($keys, [System.StringComparer]::Ordinal)
            $sorted = [ordered]@{}
            foreach ($key in $keys) { $sorted[$key] = & $sort $Value[$key] }
            return $sorted
        }
        if ($Value -is [System.Collections.IEnumerable]) {
            return , @(foreach ($item in $Value) { , (& $sort $item) })
        }
        $names = [string[]]@($Value.PSObject.Properties | ForEach-Object { $_.Name })
        [Array]::Sort($names, [System.StringComparer]::Ordinal)
        $sorted = [ordered]@{}
        foreach ($name in $names) { $sorted[$name] = & $sort $Value.$name }
        $sorted
    }

    ConvertTo-Json -InputObject (& $sort $InputObject) -Depth 100 -Compress
}

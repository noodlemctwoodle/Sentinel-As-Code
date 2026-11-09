#Requires -Version 7.6

<#
.SYNOPSIS
    Write a template value (object, array, string, number, bool, null) as
    Bicep.

.NOTES
    File:         Modules/iSOCDeployments/Private/Bicep/ConvertTo-iSOCBicepValue.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-06
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function ConvertTo-iSOCBicepValue {
    <#
    .SYNOPSIS
        Return the Bicep text of a value, indented for its depth.

    .DESCRIPTION
        - An object is written one property per line, and an array one item
          per line, two spaces deeper than the line it opens on; an empty one
          is {} or []. A key that is not an identifier is quoted ('$schema',
          'Add_comment_(V3)').
        - A string that is an ARM expression ([...]) becomes the Bicep
          expression; one escaped with [[ loses the first bracket and is a
          literal; any other string is a literal, multi-line text as a '''
          block where it can be.
        - Integers are written as they are, and other numbers as json('1.5')
          so no precision is lost. A DateTime (from ConvertFrom-Json) is
          written as the text ConvertTo-Json gives it, so the JSON and Bicep
          exports agree.

    .PARAMETER Value
        The value: dictionaries (or [pscustomobject]), arrays and plain
        values.

    .PARAMETER Symbols
        The symbol table (see ConvertTo-iSOCBicepExpression).

    .PARAMETER Depth
        The indentation depth of the line the value starts on.

    .OUTPUTS
        [string] The Bicep text, without a trailing line feed.

    .EXAMPLE
        ConvertTo-iSOCBicepValue -Value $resource.properties -Symbols $symbols -Depth 1
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [object] $Value,

        [Parameter(Mandatory)]
        [psobject] $Symbols,

        [int] $Depth = 0
    )

    $inner = '  ' * ($Depth + 1)
    $outer = '  ' * $Depth

    if ($null -eq $Value) { return 'null' }
    if ($Value -is [bool]) { return $(if ($Value) { 'true' } else { 'false' }) }
    if ($Value -is [string]) {
        if ($Value.StartsWith('[[')) { return (ConvertTo-iSOCBicepString -Value $Value.Substring(1) -AllowMultiLine) }
        if ($Value.Length -ge 2 -and $Value.StartsWith('[') -and $Value.EndsWith(']')) {
            return (ConvertTo-iSOCBicepExpression -Node (ConvertFrom-iSOCArmExpression -Expression $Value.Substring(1, $Value.Length - 2)) -Symbols $Symbols)
        }
        return (ConvertTo-iSOCBicepString -Value $Value -AllowMultiLine)
    }
    if ($Value -is [datetime] -or $Value -is [datetimeoffset]) {
        return (ConvertTo-iSOCBicepString -Value ((ConvertTo-Json -InputObject $Value -Compress).Trim('"')))
    }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [short] -or $Value -is [byte] -or $Value -is [System.Numerics.BigInteger]) {
        return $Value.ToString([System.Globalization.CultureInfo]::InvariantCulture)
    }
    if ($Value -is [double] -or $Value -is [decimal] -or $Value -is [single]) {
        return "json('" + $Value.ToString('R', [System.Globalization.CultureInfo]::InvariantCulture).Replace('E+', 'E') + "')"
    }

    if ($Value -is [System.Collections.IDictionary] -or $Value -is [System.Management.Automation.PSCustomObject]) {
        $entries = @(Get-iSOCPropertyEntry -InputObject $Value)
        if ($entries.Count -eq 0) { return '{}' }
        $lines = foreach ($entry in $entries) {
            $label = if ($entry.Name -match '^[A-Za-z_][A-Za-z0-9_]*$') { $entry.Name } else { ConvertTo-iSOCBicepString -Value $entry.Name }
            "${inner}${label}: $(ConvertTo-iSOCBicepValue -Value $entry.Value -Symbols $Symbols -Depth ($Depth + 1))"
        }
        return "{`n" + ($lines -join "`n") + "`n$outer}"
    }

    if ($Value -is [System.Collections.IEnumerable]) {
        $items = @($Value)
        if ($items.Count -eq 0) { return '[]' }
        $lines = foreach ($item in $items) { "$inner$(ConvertTo-iSOCBicepValue -Value $item -Symbols $Symbols -Depth ($Depth + 1))" }
        return "[`n" + ($lines -join "`n") + "`n$outer]"
    }

    throw "Cannot write a $($Value.GetType().FullName) value as Bicep."
}

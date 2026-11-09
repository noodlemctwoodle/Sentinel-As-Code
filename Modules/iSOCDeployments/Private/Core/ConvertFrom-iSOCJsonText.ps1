#Requires -Version 7.6

<#
.SYNOPSIS
    Parse JSON text without turning dates into DateTime values.

.DESCRIPTION
    ConvertFrom-Json in PowerShell 7 reads a string that looks like a date
    (2026-01-02T03:04:05Z) as a DateTime, so writing the value again can
    change its text. Templates hold such strings (a recurrence trigger's
    startTime), and the Bicep writer and the template comparison need them
    exactly as written. This reads through Newtonsoft.Json, which PowerShell
    7 ships, with date parsing turned off.

.NOTES
    File:         Modules/iSOCDeployments/Private/Core/ConvertFrom-iSOCJsonText.ps1
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

function ConvertFrom-iSOCJsonText {
    <#
    .SYNOPSIS
        Return JSON text as ordered dictionaries, arrays and plain values.

    .DESCRIPTION
        Objects become ordered dictionaries with case-sensitive keys, in the
        order the text gives them; arrays become object arrays (a one-item
        array stays an array); strings stay strings, dates included;
        integers become Int64 and other numbers Double; true, false and null
        stay what they are.

    .PARAMETER Text
        The JSON text.

    .OUTPUTS
        [object] The parsed value.

    .EXAMPLE
        $template = ConvertFrom-iSOCJsonText -Text (Get-Content -LiteralPath $path -Raw)
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    $reader = [Newtonsoft.Json.JsonTextReader]::new([System.IO.StringReader]::new($Text))
    $reader.DateParseHandling = [Newtonsoft.Json.DateParseHandling]::None
    try { $token = [Newtonsoft.Json.Linq.JToken]::ReadFrom($reader) }
    finally { $reader.Close() }

    # get_Type() rather than .Type: a JObject is a dictionary, so PowerShell
    # would read .Type as the value of a key named Type.
    $convert = {
        param($Token)
        switch ($Token.get_Type().ToString()) {
            'Object' {
                $map = [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::Ordinal)
                foreach ($property in $Token.Properties()) { $map[$property.Name] = & $convert $property.Value }
                return $map
            }
            'Array' {
                $items = [System.Collections.Generic.List[object]]::new()
                foreach ($child in $Token.Children()) { $items.Add((& $convert $child)) }
                return , $items.ToArray()
            }
            'Null' { return $null }
            default { return $Token.Value }
        }
    }
    & $convert $token
}

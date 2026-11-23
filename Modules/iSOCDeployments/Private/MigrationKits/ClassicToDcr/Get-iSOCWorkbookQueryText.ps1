#Requires -Version 7.6

<#
.SYNOPSIS
    Every query in a workbook's serialised content.

.DESCRIPTION
    Walks the parsed serializedData and collects each string value of a
    property named query, at any depth.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/ClassicToDcr/Get-iSOCWorkbookQueryText.ps1
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

function Get-iSOCWorkbookQueryText {
    <#
    .SYNOPSIS
        Every query in a workbook's serialised content.

    .DESCRIPTION
        Parses serializedData and walks it, collecting the string value of
        every property named query at any depth. Content that is missing or
        is not JSON has no queries.

    .PARAMETER SerializedData
        The workbook's properties.serializedData.

    .OUTPUTS
        [string[]]

    .EXAMPLE
        Get-iSOCWorkbookQueryText -SerializedData $workbook.properties.serializedData
    #>
    [CmdletBinding()]
    [OutputType([string[]], [object[]])]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string] $SerializedData
    )

    if (-not $SerializedData) { return @() }
    try {
        $parsed = $SerializedData | ConvertFrom-Json -Depth 20
    } catch { return @() }

    $queries = [System.Collections.Generic.List[string]]::new()
    $walk = {
        param($Node)
        if ($null -eq $Node) { return }
        if ($Node -is [System.Collections.IEnumerable] -and -not ($Node -is [string])) {
            foreach ($child in $Node) { & $walk $child }
            return
        }
        if ($Node -is [PSCustomObject] -or $Node -is [hashtable]) {
            $names = if ($Node -is [hashtable]) { @($Node.Keys) } else { @($Node.PSObject.Properties.Name) }
            foreach ($name in $names) {
                $value = $Node.$name
                if ($name -eq 'query' -and $value -is [string]) { $queries.Add($value) }
                & $walk $value
            }
        }
    }
    & $walk $parsed
    $queries.ToArray()
}

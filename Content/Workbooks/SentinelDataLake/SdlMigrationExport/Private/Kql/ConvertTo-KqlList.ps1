#Requires -Version 7.2

<#
.SYNOPSIS
    Converts names into the body of a KQL dynamic string array.

.NOTES
    File:         Content/Workbooks/SentinelDataLake/SdlMigrationExport/Private/Kql/ConvertTo-KqlList.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.2.0
    Last Updated: 2026-11-16
    Requires:     PowerShell 7.2+

    Defines one function, dot-sourced by Export-SdlMigrationWorkbook.ps1
    (deprecated; to be replaced by the iSOCDeployments module).
#>

# Keeps the file help above from being read as the help of the function below.

function ConvertTo-KqlList {
    <#
    .SYNOPSIS
        Converts names into the body of a KQL dynamic string array.

    .DESCRIPTION
        Returns the quoted, comma-separated items for dynamic([...]).
        An empty list becomes a single empty string so the KQL still
        parses.

    .PARAMETER Item
        The names to quote.

    .OUTPUTS
        [string] The list body.
    #>
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([string])]
    param (
        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]]$Item
    )

    if (-not $Item -or $Item.Count -eq 0) {
        return "''"
    }
    $quoted = foreach ($name in $Item) {
        "'$name'"
    }
    return ($quoted -join ',')
}

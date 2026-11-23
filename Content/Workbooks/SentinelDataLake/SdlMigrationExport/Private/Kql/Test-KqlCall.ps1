#Requires -Version 7.6

<#
.SYNOPSIS
    Tests whether a function is called in cleaned KQL.

.NOTES
    File:         Content/Workbooks/SentinelDataLake/SdlMigrationExport/Private/Kql/Test-KqlCall.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.2.0
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    Defines one function, dot-sourced by Export-SdlMigrationWorkbook.ps1
    (deprecated; to be replaced by the iSOCDeployments module).
#>

# Keeps the file help above from being read as the help of the function below.

function Test-KqlCall {
    <#
    .SYNOPSIS
        Tests whether a function is called in cleaned KQL.

    .DESCRIPTION
        Matches Alias(...) and not a bare word or a member access, so
        a column that shares the function's name is not counted.

    .PARAMETER CleanText
        KQL text from Get-KqlCodeText.

    .PARAMETER Alias
        The function alias.

    .OUTPUTS
        [bool] True when the function is called.
    #>
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$CleanText,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Alias
    )

    return [regex]::IsMatch($CleanText, ('(?<![\w.])' + [regex]::Escape($Alias) + '\s*\('))
}

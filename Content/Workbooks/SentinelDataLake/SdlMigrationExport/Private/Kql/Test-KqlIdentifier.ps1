#Requires -Version 7.2

<#
.SYNOPSIS
    Tests whether a name is used as an identifier in cleaned KQL.

.NOTES
    File:         Content/Workbooks/SentinelDataLake/SdlMigrationExport/Private/Kql/Test-KqlIdentifier.ps1
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

function Test-KqlIdentifier {
    <#
    .SYNOPSIS
        Tests whether a name is used as an identifier in cleaned KQL.

    .DESCRIPTION
        Matches the name only when it is not part of a longer word and
        not a member access (x.Name).

    .PARAMETER CleanText
        KQL text from Get-KqlCodeText.

    .PARAMETER Name
        The identifier to look for.

    .OUTPUTS
        [bool] True when the name is used.
    #>
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$CleanText,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    return [regex]::IsMatch($CleanText, ('(?<![\w.])' + [regex]::Escape($Name) + '(?!\w)'))
}

#Requires -Version 7.2

<#
.SYNOPSIS
    Pairs each rule that has a query with its cleaned query text.

.NOTES
    File:         Content/Workbooks/SentinelDataLake/SdlMigrationExport/Private/Rule/Get-SdlRuleBody.ps1
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

function Get-SdlRuleBody {
    <#
    .SYNOPSIS
        Pairs each rule that has a query with its cleaned query text.

    .DESCRIPTION
        Rules without a query (Fusion, Microsoft security, ML) are
        skipped. The cleaned text has comments and string literals
        blanked (Get-KqlCodeText).

    .PARAMETER Rule
        Rule rows from Get-SdlRuleInventory.

    .OUTPUTS
        [pscustomobject] Rule and Clean.
    #>
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([pscustomobject])]
    param (
        [Parameter()]
        [AllowEmptyCollection()]
        [object[]]$Rule = @()
    )

    foreach ($entry in $Rule) {
        if (-not $entry.QueryText) {
            continue
        }
        [pscustomobject]@{
            Rule  = $entry
            Clean = Get-KqlCodeText -Text $entry.QueryText
        }
    }
}

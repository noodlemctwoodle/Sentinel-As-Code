#Requires -Version 7.2

<#
.SYNOPSIS
    Lists which enabled rules call which workspace function.

.NOTES
    File:         Content/Workbooks/SentinelDataLake/SdlMigrationExport/Private/Rule/Get-SdlFunctionRuleMap.ps1
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

function Get-SdlFunctionRuleMap {
    <#
    .SYNOPSIS
        Lists which enabled rules call which workspace function.

    .DESCRIPTION
        One row per (function, rule) pair where the rule calls the
        function.

    .PARAMETER RuleBody
        Rule bodies from Get-SdlRuleBody.

    .PARAMETER Function
        Function rows from Get-SdlFunctionInventory.

    .OUTPUTS
        [pscustomobject] FunctionAlias, RuleName, Kind and Severity.
    #>
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([pscustomobject])]
    param (
        [Parameter()]
        [AllowEmptyCollection()]
        [object[]]$RuleBody = @(),

        [Parameter()]
        [AllowEmptyCollection()]
        [object[]]$Function = @()
    )

    foreach ($entry in $Function) {
        if (-not $entry.FunctionAlias) {
            continue
        }
        foreach ($body in $RuleBody) {
            if (Test-KqlCall -CleanText $body.Clean -Alias $entry.FunctionAlias) {
                [pscustomobject]@{
                    FunctionAlias = $entry.FunctionAlias
                    RuleName      = $body.Rule.RuleName
                    Kind          = $body.Rule.Kind
                    Severity      = $body.Rule.Severity
                }
            }
        }
    }
}

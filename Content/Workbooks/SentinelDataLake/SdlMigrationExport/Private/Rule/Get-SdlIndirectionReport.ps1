#Requires -Version 7.6

<#
.SYNOPSIS
    Lists the rules that reach data indirectly.

.NOTES
    File:         Content/Workbooks/SentinelDataLake/SdlMigrationExport/Private/Rule/Get-SdlIndirectionReport.ps1
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

function Get-SdlIndirectionReport {
    <#
    .SYNOPSIS
        Lists the rules that reach data indirectly.

    .DESCRIPTION
        A rule is listed when it calls an ASIM parser (_Im_ or _ASim_,
        any case), _GetWatchlist, externaldata or a workspace
        function, because a plain table-name scan misses the tables
        behind them.

    .PARAMETER RuleBody
        Rule bodies from Get-SdlRuleBody.

    .PARAMETER Function
        Function rows from Get-SdlFunctionInventory.

    .OUTPUTS
        [pscustomobject] One row per indirect rule.
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

    foreach ($body in $RuleBody) {
        $clean = $body.Clean
        $asim = @([regex]::Matches($clean, '(?<![\w.])_(?:Im|ASim)_\w+', 'IgnoreCase') | ForEach-Object -Process { $_.Value } | Sort-Object -Unique)
        $watchlist = $clean -cmatch '_GetWatchlist\s*\('
        $external = $clean -cmatch '(?<![\w.])externaldata\s*\('
        $customFunction = @($Function | Where-Object -FilterScript { $_.FunctionAlias -and (Test-KqlCall -CleanText $clean -Alias $_.FunctionAlias) } | ForEach-Object -Process { $_.FunctionAlias } | Sort-Object -Unique)
        if ($asim.Count -gt 0 -or $watchlist -or $external -or $customFunction.Count -gt 0) {
            [pscustomobject]@{
                RuleName         = $body.Rule.RuleName
                Kind             = $body.Rule.Kind
                Severity         = $body.Rule.Severity
                AsimParsers      = ($asim -join '; ')
                UsesWatchlistFn  = $watchlist
                UsesExternalData = $external
                CustomFnCalls    = ($customFunction -join '; ')
            }
        }
    }
}

#Requires -Version 7.2

<#
.SYNOPSIS
    Lists every rule-to-table reference with the route it takes.

.NOTES
    File:         Content/Workbooks/SentinelDataLake/SdlMigrationExport/Private/Rule/Get-SdlRuleReference.ps1
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

function Get-SdlRuleReference {
    <#
    .SYNOPSIS
        Lists every rule-to-table reference with the route it takes.

    .DESCRIPTION
        A rule references a table directly (identifier match), through
        the legacy ThreatIntelligenceIndicator alias (counted against
        the new TI tables), through _GetWatchlist (the Watchlist
        table) or through a workspace function that reaches the table.

    .PARAMETER FunctionReach
        The hashtable from Get-SdlFunctionReach.

    .PARAMETER RuleBody
        Rule bodies from Get-SdlRuleBody.

    .PARAMETER TableUniverse
        The table names to look for.

    .OUTPUTS
        [pscustomobject] Table, RuleId, RuleName, Kind, Severity and Via.
    #>
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)]
        [hashtable]$FunctionReach,

        [Parameter()]
        [AllowEmptyCollection()]
        [object[]]$RuleBody = @(),

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]]$TableUniverse = @()
    )

    foreach ($body in $RuleBody) {
        $routes = @(
            foreach ($table in $TableUniverse) {
                if (Test-KqlIdentifier -CleanText $body.Clean -Name $table) {
                    [pscustomobject]@{ Table = $table; Via = 'Direct' }
                }
            }
            if (Test-KqlIdentifier -CleanText $body.Clean -Name 'ThreatIntelligenceIndicator') {
                foreach ($newTable in @('ThreatIntelIndicators', 'ThreatIntelObjects')) {
                    if ($TableUniverse -contains $newTable) {
                        [pscustomobject]@{ Table = $newTable; Via = 'Legacy TI alias' }
                    }
                }
            }
            if ($body.Clean -cmatch '_GetWatchlist\s*\(' -and $TableUniverse -contains 'Watchlist') {
                [pscustomobject]@{ Table = 'Watchlist'; Via = '_GetWatchlist' }
            }
            foreach ($alias in @($FunctionReach.Keys)) {
                if ($FunctionReach[$alias].Tables.Count -gt 0 -and (Test-KqlCall -CleanText $body.Clean -Alias $alias)) {
                    foreach ($table in $FunctionReach[$alias].Tables) {
                        [pscustomobject]@{ Table = $table; Via = "Function $alias" }
                    }
                }
            }
        )
        foreach ($route in $routes) {
            [pscustomobject]@{
                Table    = $route.Table
                RuleId   = $body.Rule.RuleId
                RuleName = $body.Rule.RuleName
                Kind     = $body.Rule.Kind
                Severity = $body.Rule.Severity
                Via      = $route.Via
            }
        }
    }
}

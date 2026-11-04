#Requires -Version 7.2

<#
.SYNOPSIS
    What would make a dependency fixture unsafe or meaningless: an alias that shadows something, or content that names the wrong table.

.DESCRIPTION
    Checked before anything is written: each alias against the workspace's
    tables, known tables and others' parsers, and the queries against what
    they must not name.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/Rehearsal/Get-iSOCDependencyFixtureProblem.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.0
    Last Updated: 2026-11-04
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCDependencyFixtureProblem {
    <#
    .SYNOPSIS
        What would make a dependency fixture unsafe or meaningless: an alias
        that shadows something, or content that names the wrong table.

    .DESCRIPTION
        AliasProblem: each alias that would shadow a workspace table, a known
        table or another saved search's alias (Get-iSOCAliasCollisionReason).
        QueryProblem: an indirect rule or the hunting query that names a
        fixture table (it would prove nothing), and any fixture query that
        names the orphan table (it could not prove the absence of
        over-reporting). Matching is the review's own
        (Test-iSOCKqlTableReference), the only honest test.

    .PARAMETER Fixture
        From Get-iSOCDependencyFixturePlan.

    .PARAMETER MappingPath
        The solution mapping, for the known table names.

    .OUTPUTS
        [pscustomobject] AliasProblem and QueryProblem.

    .EXAMPLE
        Get-iSOCDependencyFixtureProblem -Fixture $fixture
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Fixture,

        [string] $MappingPath = (Join-Path $script:iSOCDeploymentsRoot 'Resources/ClassicToDcr/solution-mapping.json')
    )

    $plan = $Fixture.Plan
    $aliasProblem = [System.Collections.Generic.List[string]]::new()
    $reservedName = Get-iSOCReservedTableName -MappingPath $MappingPath
    foreach ($alias in $plan.Alias) {
        $reason = Get-iSOCAliasCollisionReason -Alias $alias -WorkspaceTableName $Fixture.WorkspaceTableName -ReservedName $reservedName -ForeignAlias $Fixture.ForeignAlias
        if ($reason) { $aliasProblem.Add($reason) }
    }

    $queryProblem = [System.Collections.Generic.List[string]]::new()
    foreach ($rule in ($plan.Rule | Where-Object { $_.IsIndirect })) {
        foreach ($tableName in $Fixture.ExpectedTableName) {
            if (Test-iSOCKqlTableReference -Query $rule.Query -TableName $tableName) {
                $queryProblem.Add("indirect rule '$($rule.DisplayName)' names table '$tableName' in its query, which would make the fixture prove nothing")
            }
        }
    }
    foreach ($hunt in $plan.HuntingQuery) {
        foreach ($tableName in $Fixture.ExpectedTableName) {
            if (Test-iSOCKqlTableReference -Query $hunt.Query -TableName $tableName) {
                $queryProblem.Add("hunting query '$($hunt.SavedSearchId)' names table '$tableName' in its query, which would make the fixture prove nothing")
            }
        }
    }
    $everyQuery = @($plan.Parser | ForEach-Object { $_.Query }) + @($plan.HuntingQuery | ForEach-Object { $_.Query }) + @($plan.Rule | ForEach-Object { $_.Query })
    foreach ($orphanTable in @($plan.Table | Where-Object { $_.ScenarioName -eq 'Orphan' })) {
        foreach ($query in $everyQuery) {
            if (Test-iSOCKqlTableReference -Query $query -TableName $orphanTable.TableName) {
                $queryProblem.Add("the orphan table '$($orphanTable.TableName)' is referenced by fixture content, so it could not prove the absence of over-reporting")
            }
        }
    }

    [pscustomobject]@{ AliasProblem = $aliasProblem.ToArray(); QueryProblem = $queryProblem.ToArray() }
}

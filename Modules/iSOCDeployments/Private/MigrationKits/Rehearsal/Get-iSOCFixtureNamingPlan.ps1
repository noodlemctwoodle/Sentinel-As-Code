#Requires -Version 7.6

<#
.SYNOPSIS
    Build everything a dependency fixture will create: tables, parsers, the hunting query and the rules, with their KQL.

.DESCRIPTION
    Everything downstream reads this one structure, so the plan, the create
    path and the removal path agree on what the fixture is.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/Rehearsal/Get-iSOCFixtureNamingPlan.ps1
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

function Get-iSOCFixtureNamingPlan {
    <#
    .SYNOPSIS
        Build everything a dependency fixture will create: tables, parsers,
        the hunting query and the rules, with their KQL.

    .DESCRIPTION
        The plan banner, the create path and the removal path all read this
        one structure, so they agree by construction:

          Direct  <prefix>Direct_CL, and a rule naming it
          OneHop  <prefix>OneHop_CL, a parser over it, and a rule naming
                  only the parser
          TwoHop  <prefix>TwoHop_CL, an inner parser, an outer parser over
                  the inner, and a rule naming only the outer
          Cycle   <prefix>Cycle_CL, two parsers naming each other (one also
                  reads the table), written in three steps since a true
                  cycle cannot be made in two, and a rule naming the table:
                  a rule on a cycle member would never validate
          Orphan  <prefix>Orphan_CL with nothing pointing at it
          Hunt    a hunting query reaching OneHop's table through its parser

        An indirect query never contains a table name, comments included,
        or the fixture would prove nothing. Parsers are in dependency order,
        so a partial failure never leaves one pointing at an alias that does
        not exist yet.

    .PARAMETER NamePrefix
        The prefix on every object.

    .PARAMETER ScenarioName
        The scenarios. Defaults to all of them.

    .PARAMETER QueryClamp
        Appended to every rule query; empty authors the rules without it.

    .OUTPUTS
        [pscustomobject] NamePrefix, ScenarioName, Table, Parser,
        HuntingQuery, Rule and Alias.

    .EXAMPLE
        Get-iSOCFixtureNamingPlan -NamePrefix SacDep -QueryClamp '| where 1 == 0'
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $NamePrefix,

        [AllowEmptyCollection()]
        [AllowNull()]
        [string[]] $ScenarioName,

        [AllowEmptyString()]
        [string] $QueryClamp = (Get-iSOCDependencyFixtureSetting).QueryClamp
    )

    $markerColumn = (Get-iSOCDependencyFixtureSetting).MarkerColumnName
    $wanted = Resolve-iSOCFixtureScenario -Scenario $ScenarioName
    $tableFor = { param([string] $Suffix) "${NamePrefix}${Suffix}_CL" }

    $oneHopTable = & $tableFor 'OneHop'
    $twoHopTable = & $tableFor 'TwoHop'
    $cycleTable = & $tableFor 'Cycle'
    $directTable = & $tableFor 'Direct'
    $orphanTable = & $tableFor 'Orphan'

    $aliasOneHop = "${NamePrefix}OneHopParser"
    $aliasInner = "${NamePrefix}InnerParser"
    $aliasOuter = "${NamePrefix}OuterParser"
    $aliasCycleA = "${NamePrefix}CycleA"
    $aliasCycleB = "${NamePrefix}CycleB"
    $projection = "| project TimeGenerated, SourceHost_s, Severity_s, $markerColumn"

    $allTable = @(
        [pscustomobject]@{ ScenarioName = 'Direct'; LogType = "${NamePrefix}Direct"; TableName = $directTable }
        [pscustomobject]@{ ScenarioName = 'OneHop'; LogType = "${NamePrefix}OneHop"; TableName = $oneHopTable }
        [pscustomobject]@{ ScenarioName = 'TwoHop'; LogType = "${NamePrefix}TwoHop"; TableName = $twoHopTable }
        [pscustomobject]@{ ScenarioName = 'Cycle'; LogType = "${NamePrefix}Cycle"; TableName = $cycleTable }
        [pscustomobject]@{ ScenarioName = 'Orphan'; LogType = "${NamePrefix}Orphan"; TableName = $orphanTable }
    )

    $parser = {
        param($Scenario, $Id, $Alias, $DisplayName, $Query, $Order, $Closure)
        [pscustomobject]@{ ScenarioName = $Scenario; SavedSearchId = $Id; Alias = $Alias; DisplayName = $DisplayName; Query = $Query; Order = $Order; IsCycleClosure = $Closure }
    }
    $allParser = @(
        & $parser 'OneHop' "${NamePrefix}-OneHopParser" $aliasOneHop "$NamePrefix fixture one-hop parser" "$oneHopTable`n$projection" 1 $false
        & $parser 'TwoHop' "${NamePrefix}-InnerParser" $aliasInner "$NamePrefix fixture inner parser" "$twoHopTable`n$projection" 2 $false
        & $parser 'TwoHop' "${NamePrefix}-OuterParser" $aliasOuter "$NamePrefix fixture outer parser" "$aliasInner`n| where isnotempty(SourceHost_s)" 3 $false
        & $parser 'Cycle' "${NamePrefix}-CycleA" $aliasCycleA "$NamePrefix fixture cycle parser A" "$cycleTable`n$projection" 4 $false
        & $parser 'Cycle' "${NamePrefix}-CycleB" $aliasCycleB "$NamePrefix fixture cycle parser B" "$aliasCycleA`n| where isnotempty(SourceHost_s)" 5 $false
        & $parser 'Cycle' "${NamePrefix}-CycleA" $aliasCycleA "$NamePrefix fixture cycle parser A" "union $cycleTable, $aliasCycleB`n| project TimeGenerated, SourceHost_s" 6 $true
    )

    $allHunt = @(
        [pscustomobject]@{
            ScenarioName  = 'Hunt'
            SavedSearchId = "${NamePrefix}-Hunt"
            DisplayName   = "$NamePrefix fixture hunting query via parser"
            Query         = "$aliasOneHop`n| summarize Hits = count() by SourceHost_s"
        }
    )

    $clampLine = if ([string]::IsNullOrWhiteSpace($QueryClamp)) { '' } else { "`n$QueryClamp" }
    $allRule = @(
        [pscustomobject]@{ ScenarioName = 'Direct'; DisplayName = "$NamePrefix fixture - direct table reference"; Query = "$directTable$clampLine"; IsIndirect = $false }
        [pscustomobject]@{ ScenarioName = 'OneHop'; DisplayName = "$NamePrefix fixture - one hop through a parser"; Query = "$aliasOneHop$clampLine"; IsIndirect = $true }
        [pscustomobject]@{ ScenarioName = 'TwoHop'; DisplayName = "$NamePrefix fixture - two hops through parsers"; Query = "$aliasOuter$clampLine"; IsIndirect = $true }
        [pscustomobject]@{ ScenarioName = 'Cycle'; DisplayName = "$NamePrefix fixture - table also read by a cyclic parser pair"; Query = "$cycleTable$clampLine"; IsIndirect = $false }
    )
    foreach ($rule in $allRule) {
        Add-Member -InputObject $rule -NotePropertyName 'RuleId' -NotePropertyValue (New-iSOCFixtureRuleId -NamePrefix $NamePrefix -ScenarioName $rule.ScenarioName)
    }

    [pscustomobject]@{
        NamePrefix   = $NamePrefix
        ScenarioName = @($wanted)
        Table        = @($allTable | Where-Object { $wanted -contains $_.ScenarioName })
        Parser       = @($allParser | Where-Object { $wanted -contains $_.ScenarioName } | Sort-Object Order)
        HuntingQuery = @($allHunt | Where-Object { $wanted -contains $_.ScenarioName })
        Rule         = @($allRule | Where-Object { $wanted -contains $_.ScenarioName })
        Alias        = @($allParser | Where-Object { $wanted -contains $_.ScenarioName } | Select-Object -ExpandProperty Alias -Unique)
    }
}

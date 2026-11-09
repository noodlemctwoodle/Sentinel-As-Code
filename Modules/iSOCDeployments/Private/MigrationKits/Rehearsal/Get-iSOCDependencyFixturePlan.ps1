#Requires -Version 7.6

<#
.SYNOPSIS
    Read the workspace and plan what a dependency fixture run does with each object.

.DESCRIPTION
    Read-only, so it runs under -WhatIf: the onboarding state, the tables,
    saved searches and rules, and an action for every fixture object.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/Rehearsal/Get-iSOCDependencyFixturePlan.ps1
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

function Get-iSOCDependencyFixturePlan {
    <#
    .SYNOPSIS
        Read the workspace and plan what a dependency fixture run does with
        each object.

    .DESCRIPTION
        Read-only, so it runs under -WhatIf, since it is what makes the plan
        real. Microsoft Sentinel must be onboarded (a workspace without it
        throws: the rules could never be made, and half a fixture is worse
        than none); an onboarding state that cannot be read is a warning.
        The tables, saved searches and analytics rules are read, and each
        fixture object gets an action (Get-iSOCFixtureObjectAction) by
        whether it exists and is provably the fixture's. For a removal,
        saved searches with the prefix and the marker that are not in the
        plan (from a run with other scenarios) are added as strays to
        delete.

    .PARAMETER Context
        The workspace context.

    .PARAMETER NamePrefix
        The fixture prefix.

    .PARAMETER Scenario
        The scenarios.

    .PARAMETER QueryClamp
        The clamp for the rule queries.

    .PARAMETER ForRemoval
        Plan a removal.

    .OUTPUTS
        [pscustomobject] Plan (from Get-iSOCFixtureNamingPlan), Rows,
        WorkspaceTableName, ForeignAlias, ExpectedTableName, WorkspaceBase
        and SentinelBase.

    .EXAMPLE
        $fixture = Get-iSOCDependencyFixturePlan -Context $ctx -NamePrefix SacDep -QueryClamp '| where 1 == 0'
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Context,

        [Parameter(Mandatory)]
        [string] $NamePrefix,

        [AllowEmptyCollection()]
        [AllowNull()]
        [string[]] $Scenario,

        [AllowEmptyString()]
        [string] $QueryClamp,

        [switch] $ForRemoval
    )

    $setting = Get-iSOCDependencyFixtureSetting
    $marker = $setting.FixtureMarker
    $workspaceBase = $Context.WorkspaceResourceId
    $sentinelBase = "$workspaceBase/providers/Microsoft.SecurityInsights"
    $plan = Get-iSOCFixtureNamingPlan -NamePrefix $NamePrefix -ScenarioName $Scenario -QueryClamp $QueryClamp

    Write-iSOCLog 'Preflight' -Level Section
    $onboarded = $true
    try {
        $state = Invoke-iSOCRestRequest -Method GET -Path "$sentinelBase/onboardingStates/default" -ApiVersion (Get-iSOCApiVersion SecurityInsights) -AllowNotFound
        if ($null -eq $state) { $onboarded = $false }
    }
    catch {
        Write-iSOCLog "Could not confirm the Sentinel onboarding state ($($_.Exception.Message.Split([char]10)[0])). Continuing, but analytics rule creation may fail." -Level Warning
    }
    if (-not $onboarded) {
        throw "Microsoft Sentinel is not onboarded on workspace '$($Context.WorkspaceName)'. The analytics rules could never be created, and a partial fixture is worse than none."
    }

    $existingTable = @(Invoke-iSOCRestRequest -Method GET -Path "$workspaceBase/tables" -ApiVersion (Get-iSOCApiVersion OperationalInsights))
    $existingSaved = @(Invoke-iSOCRestRequest -Method GET -Path "$workspaceBase/savedSearches" -ApiVersion (Get-iSOCApiVersion SavedSearches))
    $existingRule = @(Invoke-iSOCRestRequest -Method GET -Path "$sentinelBase/alertRules" -ApiVersion (Get-iSOCApiVersion SecurityInsights))
    Write-iSOCLog "Read $($existingTable.Count) tables, $($existingSaved.Count) saved searches, $($existingRule.Count) analytics rules."

    $workspaceTableName = @($existingTable | ForEach-Object { [string](Get-iSOCPropertyValue -InputObject $_ -Path 'name') } | Where-Object { $_ })
    $expectedRuleId = @($plan.Rule | Select-Object -ExpandProperty RuleId -Unique)
    $expectedTableName = @($plan.Table | Select-Object -ExpandProperty TableName -Unique)
    $foreignAlias = @($existingSaved | Where-Object { -not (Test-iSOCFixtureOwnedSavedSearch -SavedSearch $_ -FixtureMarker $marker) } | ForEach-Object {
            $alias = [string](Get-iSOCPropertyValue -InputObject $_ -Path 'properties.functionAlias')
            if (-not [string]::IsNullOrWhiteSpace($alias)) { $alias }
        })

    $rows = [System.Collections.Generic.List[pscustomobject]]::new()
    $add = {
        param($Type, $Name, $ResourceId, $ScenarioName, $Found, $Owned, $Marker)
        $rows.Add([pscustomobject]@{
                Type       = $Type
                Name       = $Name
                ResourceId = $ResourceId
                Scenario   = $ScenarioName
                Action     = Get-iSOCFixtureObjectAction -Existing $Found -IsOwned $Owned -ForRemoval:$ForRemoval
                Marker     = $(if ($Owned) { $Marker } else { '' })
            })
    }
    foreach ($table in $plan.Table) {
        $found = Find-iSOCItemByName -Collection $existingTable -Name $table.TableName
        $owned = Test-iSOCFixtureOwnedTable -Table $found -ExpectedTableName $expectedTableName
        & $add 'Table' $table.TableName "$workspaceBase/tables/$($table.TableName)" $table.ScenarioName $found $owned $setting.MarkerColumnName
    }
    foreach ($parser in ($plan.Parser | Where-Object { -not $_.IsCycleClosure })) {
        $found = Find-iSOCItemByName -Collection $existingSaved -Name $parser.SavedSearchId
        $owned = Test-iSOCFixtureOwnedSavedSearch -SavedSearch $found -FixtureMarker $marker
        & $add 'Parser' "$($parser.SavedSearchId) (alias $($parser.Alias))" "$workspaceBase/savedSearches/$($parser.SavedSearchId)" $parser.ScenarioName $found $owned "tag $($setting.FixtureTagName)"
    }
    foreach ($hunt in $plan.HuntingQuery) {
        $found = Find-iSOCItemByName -Collection $existingSaved -Name $hunt.SavedSearchId
        $owned = Test-iSOCFixtureOwnedSavedSearch -SavedSearch $found -FixtureMarker $marker
        & $add 'HuntingQuery' $hunt.SavedSearchId "$workspaceBase/savedSearches/$($hunt.SavedSearchId)" $hunt.ScenarioName $found $owned "tag $($setting.FixtureTagName)"
    }
    foreach ($rule in $plan.Rule) {
        $found = Find-iSOCItemByName -Collection $existingRule -Name $rule.RuleId
        $owned = Test-iSOCFixtureOwnedAlertRule -AlertRule $found -FixtureMarker $marker -ExpectedRuleId $expectedRuleId
        & $add 'AlertRule' "$($rule.RuleId)  $($rule.DisplayName)" "$sentinelBase/alertRules/$($rule.RuleId)" $rule.ScenarioName $found $owned 'derived id / description sentinel'
    }

    if ($ForRemoval) {
        $plannedSavedName = @($rows | Where-Object { $_.Type -in @('Parser', 'HuntingQuery') } | ForEach-Object { ($_.ResourceId -split '/')[-1] })
        foreach ($saved in $existingSaved) {
            $name = [string](Get-iSOCPropertyValue -InputObject $saved -Path 'name')
            if (-not $name) {
                $id = [string](Get-iSOCPropertyValue -InputObject $saved -Path 'id')
                if ($id) { $name = ($id -split '/')[-1] }
            }
            if (-not $name) { continue }
            if ($name -in $plannedSavedName) { continue }
            if ($name -notlike "$NamePrefix*") { continue }
            if (-not (Test-iSOCFixtureOwnedSavedSearch -SavedSearch $saved -FixtureMarker $marker)) { continue }
            $rows.Add([pscustomobject]@{
                    Type       = 'SavedSearch'
                    Name       = $name
                    ResourceId = "$workspaceBase/savedSearches/$name"
                    Scenario   = 'stray'
                    Action     = 'DELETE'
                    Marker     = "tag $($setting.FixtureTagName)"
                })
        }
    }

    [pscustomobject]@{
        Plan               = $plan
        Rows               = $rows.ToArray()
        WorkspaceTableName = $workspaceTableName
        ForeignAlias       = $foreignAlias
        ExpectedTableName  = $expectedTableName
        WorkspaceBase      = $workspaceBase
        SentinelBase       = $sentinelBase
    }
}

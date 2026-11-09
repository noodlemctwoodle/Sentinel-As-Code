#Requires -Version 7.6

<#
.SYNOPSIS
    Build the PUT body of a dependency fixture parser or hunting query.

.DESCRIPTION
    A parser has a function alias; a hunting query is in Hunting Queries with
    none. Both carry the ownership tags.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/Rehearsal/New-iSOCFixtureSavedSearchBody.ps1
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

function New-iSOCFixtureSavedSearchBody {
    <#
    .SYNOPSIS
        Build the PUT body of a dependency fixture parser or hunting query.

    .DESCRIPTION
        A parser is a saved search with a functionAlias; a hunting query is
        one in the Hunting Queries category without one, and the review
        classifies them on exactly that. Both carry the SacFixture,
        SacFixtureRun and SacFixtureScenario tags. etag '*' lets a re-run
        converge, which is safe only because the plan stops the run when a
        target name exists and is not the fixture's.

    .PARAMETER Category
        The saved search category.

    .PARAMETER DisplayName
        Its display name.

    .PARAMETER Query
        Its KQL.

    .PARAMETER FixtureMarker
        The marker.

    .PARAMETER RunId
        The run.

    .PARAMETER ScenarioName
        The scenario.

    .PARAMETER FunctionAlias
        The alias, for a parser.

    .OUTPUTS
        [hashtable]

    .EXAMPLE
        New-iSOCFixtureSavedSearchBody -Category 'SacDep Fixture' -DisplayName $name -Query $query -FixtureMarker $marker -RunId $runId -ScenarioName OneHop -FunctionAlias SacDepOneHopParser
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a request body; changes nothing.')]
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $Category,

        [Parameter(Mandatory)]
        [string] $DisplayName,

        [Parameter(Mandatory)]
        [string] $Query,

        [Parameter(Mandatory)]
        [string] $FixtureMarker,

        [Parameter(Mandatory)]
        [string] $RunId,

        [Parameter(Mandatory)]
        [string] $ScenarioName,

        [AllowEmptyString()]
        [string] $FunctionAlias
    )

    $setting = Get-iSOCDependencyFixtureSetting
    $properties = [ordered]@{
        category    = $Category
        displayName = $DisplayName
        query       = $Query
        version     = 2
        tags        = @(
            [ordered]@{ name = $setting.FixtureTagName; value = $FixtureMarker }
            [ordered]@{ name = $setting.FixtureRunTag; value = $RunId }
            [ordered]@{ name = $setting.FixtureScenTag; value = $ScenarioName }
        )
    }
    if (-not [string]::IsNullOrWhiteSpace($FunctionAlias)) { $properties['functionAlias'] = $FunctionAlias }
    [ordered]@{
        etag       = '*'
        properties = $properties
    }
}

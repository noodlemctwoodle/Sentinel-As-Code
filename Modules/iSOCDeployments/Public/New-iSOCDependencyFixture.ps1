#Requires -Version 7.2

<#
.SYNOPSIS
    Make known direct and parser-chained dependency chains on classic tables, to prove the migration review finds them.

.DESCRIPTION
    New-iSOCDependencyFixture replaces the create path of
    Tools/ClassicToDcr/Rehearsal/New-DependencyFixture.ps1.

.NOTES
    File:         Modules/iSOCDeployments/Public/New-iSOCDependencyFixture.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.0
    Last Updated: 2026-11-04
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter and
    per-example detail lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function New-iSOCDependencyFixture {
    <#
    .SYNOPSIS
        Make known direct and parser-chained dependency chains on classic
        tables, to prove the migration review finds them.

    .DESCRIPTION
        Get-iSOCTableMigrationImpact reports what depends on a classic table,
        including content that reaches it only through a parser, which a
        search for the table name never finds. This makes those chains for
        real, so the review can be checked against live ARM responses:

          Direct  <prefix>Direct_CL and a rule naming it
          OneHop  <prefix>OneHop_CL, a parser over it, and a rule naming
                  only the parser
          TwoHop  <prefix>TwoHop_CL, two parsers in a chain, and a rule
                  naming only the outer one
          Cycle   <prefix>Cycle_CL and two parsers naming each other, which
                  proves the resolver ends
          Orphan  <prefix>Orphan_CL with nothing on it, so over-reporting
                  shows
          Hunt    a hunting query reaching OneHop's table through its parser

        Safe to run against a live security workspace:

          - every object carries the prefix and an ownership marker (a tag,
            a column, a derived rule id or a description sentinel)
          - rules are made disabled, Informational, with incidents off and
            their query clamped with '| where 1 == 0'; -EnableRules enables
            them, and -EnableRulesWithLiveQuery as well removes the clamp
          - an alias that would shadow a workspace table, a known table or
            someone else's parser stops the run, as does any target name
            that exists without the marker; nothing is overwritten
          - every write asks confirmation (ConfirmImpact High), and -WhatIf
            reads the workspace and prints the whole plan, writing nothing

        Tables are seeded through the Data Collector API, waited on until
        they answer a query, then the parsers and hunting query are written,
        then the rules, which Sentinel validates on write. Allow ten to
        twenty minutes on a cold run. The cycle's parsers fail any live
        query, which is their point; skip them with -Scenario. A drift run
        that absorbs portal rules will pick the fixture's up: remove it in
        the same working window.

    .PARAMETER NamePrefix
        The prefix on every object: a letter then 2 to 15 letters or digits.
        Default SacDep.

    .PARAMETER Scenario
        The scenarios: Direct, OneHop, TwoHop, Cycle, Orphan or Hunt (which
        brings OneHop). Default all.

    .PARAMETER RecordCount
        Records per table, 1 to 100. Default 5; ingestion is billable.

    .PARAMETER OdsEndpointSuffix
        The Data Collector host suffix. Defaults to the Az sign-in's cloud's.

    .PARAMETER TimeoutSeconds
        The wait for each table to appear and answer a query, 60 to 3600.
        Default 900.

    .PARAMETER EnableRules
        Make the rules enabled. The clamp stays, so they still return no
        rows.

    .PARAMETER EnableRulesWithLiveQuery
        With -EnableRules, remove the clamp too, so the rules query real
        data; the only way a fixture rule can raise an alert.

    .PARAMETER Reseed
        Post records again to fixture tables that already exist.

    .PARAMETER Context
        The workspace, from Connect-iSOCWorkspace. Defaults to the
        connected one.

    .OUTPUTS
        [pscustomobject] An iSOCDeployments.DependencyFixtureRun: Mode
        (Create), NamePrefix, FixtureMarker, RunId, WorkspaceName,
        ScenarioName, RulesEnabled, Created, Skipped and Failed.

    .EXAMPLE
        New-iSOCDependencyFixture -WhatIf

        Reads the workspace and prints the plan, making nothing. Run it
        first, every time.

    .EXAMPLE
        New-iSOCDependencyFixture -Scenario OneHop, TwoHop, Hunt -Confirm:$false

        Makes only the parser chains, leaving out the cycle.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'Each seed, saved search and rule asks ShouldProcess in its private step; -WhatIf and -Confirm reach them through the preference variables.')]
    [OutputType([pscustomobject])]
    param(
        [ValidatePattern('^[A-Za-z][A-Za-z0-9]{2,15}$')]
        [string] $NamePrefix = 'SacDep',

        [ValidateSet('Direct', 'OneHop', 'TwoHop', 'Cycle', 'Orphan', 'Hunt')]
        [string[]] $Scenario,

        [ValidateRange(1, 100)]
        [int] $RecordCount = 5,

        [string] $OdsEndpointSuffix,

        [ValidateRange(60, 3600)]
        [int] $TimeoutSeconds = 900,

        [switch] $EnableRules,

        [switch] $EnableRulesWithLiveQuery,

        [switch] $Reseed,

        [psobject] $Context
    )

    if ($EnableRulesWithLiveQuery -and -not $EnableRules) {
        throw '-EnableRulesWithLiveQuery only has meaning with -EnableRules. Two separate switches are required on purpose, so neither can be reached by a typo.'
    }
    $ctx = Resolve-iSOCContext -Context $Context
    Assert-iSOCPrerequisite -Step Connect, Migrate
    Write-iSOCLog 'Dependency fixture' -Level Section
    if (-not $OdsEndpointSuffix) { $OdsEndpointSuffix = Get-iSOCDataCollectorSuffix -Context $ctx }

    $setting = Get-iSOCDependencyFixtureSetting
    $runId = [guid]::NewGuid().ToString()
    $clamp = if ($EnableRulesWithLiveQuery) { '' } else { $setting.QueryClamp }
    $fixture = Get-iSOCDependencyFixturePlan -Context $ctx -NamePrefix $NamePrefix -Scenario $Scenario -QueryClamp $clamp
    $problem = Get-iSOCDependencyFixtureProblem -Fixture $fixture
    Write-iSOCDependencyFixturePlan -Fixture $fixture -RunId $runId -EnableRules:$EnableRules -EnableRulesWithLiveQuery:$EnableRulesWithLiveQuery -RecordCount $RecordCount

    if ($problem.AliasProblem.Count -gt 0) {
        foreach ($p in $problem.AliasProblem) { Write-iSOCLog "Alias guard: $p" -Level Error }
        throw 'Refusing to create the fixture. A function alias would shadow a table or an existing parser for every query in this workspace. Pick a different -NamePrefix.'
    }
    if ($problem.QueryProblem.Count -gt 0) {
        foreach ($p in $problem.QueryProblem) { Write-iSOCLog "Fixture self-check: $p" -Level Error }
        throw 'Refusing to create the fixture. The generated content would not prove what it claims to prove.'
    }
    $abortRow = @($fixture.Rows | Where-Object { $_.Action -eq 'ABORT' })
    if ($abortRow.Count -gt 0) {
        foreach ($row in $abortRow) { Write-iSOCLog "Name collision: $($row.Type) '$($row.Name)' already exists and does not carry this fixture's marker." -Level Error }
        throw 'Refusing to create the fixture. One or more target names belong to existing content. Nothing was written. Pick a different -NamePrefix.'
    }

    $seed = Invoke-iSOCFixtureSeed -Context $ctx -Fixture $fixture -RunId $runId -RecordCount $RecordCount -OdsEndpointSuffix $OdsEndpointSuffix -Reseed:$Reseed
    Wait-iSOCFixtureQueryable -Context $ctx -Fixture $fixture -Seeded $seed.Seeded -TimeoutSeconds $TimeoutSeconds
    $saved = New-iSOCFixtureSavedSearch -Fixture $fixture -RunId $runId
    $rules = New-iSOCFixtureRule -Fixture $fixture -RunId $runId -Enabled:$EnableRules -TimeoutSeconds $TimeoutSeconds

    $created = @($seed.Created) + @($saved.Created) + @($rules.Created)
    $failed = @($seed.Failed) + @($saved.Failed) + @($rules.Failed)
    Write-iSOCLog 'Fixture summary' -Level Section
    Write-iSOCLog "  Created : $($created.Count)"
    Write-iSOCLog "  Skipped : $(@($seed.Skipped).Count)"
    Write-iSOCLog "  Failed  : $($failed.Count)"
    if ($created.Count -gt 0) {
        Write-iSOCLog ''
        Write-iSOCLog 'Now run the review and check what it reports:'
        Write-iSOCLog '  Get-iSOCTableMigrationImpact | Export-iSOCTableMigrationReport'
        Write-iSOCLog ''
        Write-iSOCLog 'Expected once transitive resolution works:'
        Write-iSOCLog "  $($NamePrefix)Direct_CL  one analytics rule (direct)"
        Write-iSOCLog "  $($NamePrefix)OneHop_CL  one parser, one analytics rule (via the parser), one hunting query (via the parser)"
        Write-iSOCLog "  $($NamePrefix)TwoHop_CL  two parsers, one analytics rule (via two parsers)"
        Write-iSOCLog "  $($NamePrefix)Cycle_CL   two parsers that reference each other, one analytics rule"
        Write-iSOCLog "  $($NamePrefix)Orphan_CL  nothing at all"
        Write-iSOCLog ''
        Write-iSOCLog "Tear it down with: Remove-iSOCDependencyFixture -NamePrefix $NamePrefix -MigrateBeforeRemove"
    }

    [pscustomobject]@{
        PSTypeName    = 'iSOCDeployments.DependencyFixtureRun'
        Mode          = 'Create'
        NamePrefix    = $NamePrefix
        FixtureMarker = $setting.FixtureMarker
        RunId         = $runId
        WorkspaceName = $ctx.WorkspaceName
        ScenarioName  = @($fixture.Plan.ScenarioName)
        RulesEnabled  = [bool]$EnableRules
        Created       = $created
        Skipped       = @($seed.Skipped)
        Failed        = $failed
    }
}

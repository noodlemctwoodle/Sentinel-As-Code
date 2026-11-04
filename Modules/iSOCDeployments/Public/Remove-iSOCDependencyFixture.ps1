#Requires -Version 7.2

<#
.SYNOPSIS
    Remove a dependency fixture: only the objects that provably carry its marker.

.DESCRIPTION
    Remove-iSOCDependencyFixture replaces
    Tools/ClassicToDcr/Rehearsal/New-DependencyFixture.ps1 -Remove.

.NOTES
    File:         Modules/iSOCDeployments/Public/Remove-iSOCDependencyFixture.ps1
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

function Remove-iSOCDependencyFixture {
    <#
    .SYNOPSIS
        Remove a dependency fixture: only the objects that provably carry
        its marker.

    .DESCRIPTION
        Reads the workspace, plans every fixture object, and deletes only
        those that carry the ownership marker: rules first, then the hunting
        query, any strays (saved searches with the prefix and the marker
        from a run with other scenarios) and the parsers, then the tables.
        Anything that only matches the prefix is reported and left. A table
        still Classic cannot be deleted by the Tables API: it is left unless
        -MigrateBeforeRemove, which migrates it first (one-way; ownership is
        proved before, never after). A table with a fixture name but no
        marker column is left unless -RemoveUnmarkedTable. Every delete
        asks confirmation (ConfirmImpact High); deleting a rule has no
        soft-delete, so run with -WhatIf first.

    .PARAMETER NamePrefix
        The fixture's prefix. Default SacDep.

    .PARAMETER Scenario
        The scenarios to remove. Default all.

    .PARAMETER MigrateBeforeRemove
        Migrate a fixture table still Classic so it can be deleted.

    .PARAMETER RemoveUnmarkedTable
        Delete a fixture-named table that has no marker column, as after a
        run stopped before its records landed. It can delete someone else's
        table, so it is never implied.

    .PARAMETER Context
        The workspace, from Connect-iSOCWorkspace. Defaults to the
        connected one.

    .OUTPUTS
        [pscustomobject] An iSOCDeployments.DependencyFixtureRun: Mode
        (Remove), NamePrefix, FixtureMarker, RunId, WorkspaceName, Removed,
        Skipped and Failed.

    .EXAMPLE
        Remove-iSOCDependencyFixture -WhatIf

        Lists each resource that would be deleted and the marker that
        qualified it.

    .EXAMPLE
        Remove-iSOCDependencyFixture -MigrateBeforeRemove -Confirm:$false

        Removes the fixture, migrating any table still classic.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'Each migration and delete asks ShouldProcess in Invoke-iSOCFixtureRemoval; -WhatIf and -Confirm reach it through the preference variables.')]
    [OutputType([pscustomobject])]
    param(
        [ValidatePattern('^[A-Za-z][A-Za-z0-9]{2,15}$')]
        [string] $NamePrefix = 'SacDep',

        [ValidateSet('Direct', 'OneHop', 'TwoHop', 'Cycle', 'Orphan', 'Hunt')]
        [string[]] $Scenario,

        [switch] $MigrateBeforeRemove,

        [switch] $RemoveUnmarkedTable,

        [psobject] $Context
    )

    $ctx = Resolve-iSOCContext -Context $Context
    Assert-iSOCPrerequisite -Step Connect
    Write-iSOCLog 'Dependency fixture' -Level Section

    $setting = Get-iSOCDependencyFixtureSetting
    $runId = [guid]::NewGuid().ToString()
    $fixture = Get-iSOCDependencyFixturePlan -Context $ctx -NamePrefix $NamePrefix -Scenario $Scenario -QueryClamp $setting.QueryClamp -ForRemoval
    Write-iSOCDependencyFixturePlan -Fixture $fixture -RunId $runId -ForRemoval
    $removal = Invoke-iSOCFixtureRemoval -Context $ctx -Fixture $fixture -MigrateBeforeRemove:$MigrateBeforeRemove -RemoveUnmarkedTable:$RemoveUnmarkedTable

    [pscustomobject]@{
        PSTypeName    = 'iSOCDeployments.DependencyFixtureRun'
        Mode          = 'Remove'
        NamePrefix    = $NamePrefix
        FixtureMarker = $setting.FixtureMarker
        RunId         = $runId
        WorkspaceName = $ctx.WorkspaceName
        Removed       = @($removal.Removed)
        Skipped       = @($removal.Skipped)
        Failed        = @($removal.Failed)
    }
}

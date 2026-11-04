#Requires -Version 7.2

<#
.SYNOPSIS
    Build a dependency fixture rule's description, ending with its ownership sentinel.

.DESCRIPTION
    What the rule is, its state, how to remove it, and the machine-readable
    '[SacFixture:<marker>:<run>:<scenario>]' line.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/Rehearsal/New-iSOCFixtureDescription.ps1
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

function New-iSOCFixtureDescription {
    <#
    .SYNOPSIS
        Build a dependency fixture rule's description, ending with its
        ownership sentinel.

    .DESCRIPTION
        Four lines: what the rule is, its state and that incidents are off,
        how to remove it, and the machine-readable
        '[SacFixture:<marker>:<run>:<scenario>]' sentinel that marks it as
        the fixture's.

    .PARAMETER NamePrefix
        The fixture prefix.

    .PARAMETER FixtureMarker
        The marker.

    .PARAMETER RunId
        The run.

    .PARAMETER ScenarioName
        The scenario.

    .PARAMETER Enabled
        Whether the rule is enabled.

    .OUTPUTS
        [string]

    .EXAMPLE
        New-iSOCFixtureDescription -NamePrefix SacDep -FixtureMarker $marker -RunId $runId -ScenarioName OneHop
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds a string; changes nothing.')]
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $NamePrefix,

        [Parameter(Mandatory)]
        [string] $FixtureMarker,

        [Parameter(Mandatory)]
        [string] $RunId,

        [Parameter(Mandatory)]
        [string] $ScenarioName,

        [bool] $Enabled = $false
    )

    $state = if ($Enabled) { 'ENABLED' } else { 'DISABLED' }
    @(
        'Dependency-detection rehearsal fixture for the classic-to-DCR migration toolkit.'
        "$state, incident creation off. Not a real detection. Safe to delete."
        "Remove with Remove-iSOCDependencyFixture -NamePrefix $NamePrefix"
        "[$((Get-iSOCDependencyFixtureSetting).FixtureTagName):${FixtureMarker}:${RunId}:${ScenarioName}]"
    ) -join "`n"
}

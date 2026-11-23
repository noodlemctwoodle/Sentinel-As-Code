#Requires -Version 7.6

<#
.SYNOPSIS
    Derive a dependency fixture rule's id from the prefix and the scenario.

.DESCRIPTION
    The first 16 bytes of a SHA-256 over the namespace, prefix and scenario,
    as the script derives it, so either can recompute the other's rules.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/Rehearsal/New-iSOCFixtureRuleId.ps1
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

function New-iSOCFixtureRuleId {
    <#
    .SYNOPSIS
        Derive a dependency fixture rule's id from the prefix and the
        scenario.

    .DESCRIPTION
        A GUID from the first 16 bytes of the SHA-256 of
        '<namespace>|<prefix>|<scenario>', exactly as
        New-DependencyFixture.ps1 derives it. A re-run converges on the same
        rule rather than adding another, and removal recomputes which rules
        are the fixture's instead of trusting a display name someone may
        have edited; a fixture made by the script is removed by the module,
        and the other way round.

    .PARAMETER NamePrefix
        The fixture prefix.

    .PARAMETER ScenarioName
        The scenario.

    .OUTPUTS
        [string]

    .EXAMPLE
        New-iSOCFixtureRuleId -NamePrefix SacDep -ScenarioName OneHop
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Derives a name; changes nothing.')]
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $NamePrefix,

        [Parameter(Mandatory)]
        [string] $ScenarioName
    )

    $seed = "$((Get-iSOCDependencyFixtureSetting).RuleIdNamespace)|$NamePrefix|$ScenarioName"
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($seed))
    } finally {
        $sha.Dispose()
    }
    ([guid]::new([byte[]]$hash[0..15])).ToString()
}

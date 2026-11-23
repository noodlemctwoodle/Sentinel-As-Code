#Requires -Version 7.6

<#
.SYNOPSIS
    Whether an analytics rule is provably the dependency fixture's.

.DESCRIPTION
    Its name is a recomputed fixture rule id, or its description carries the
    fixture sentinel; a Content Hub rule never is.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/Rehearsal/Test-iSOCFixtureOwnedAlertRule.ps1
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

function Test-iSOCFixtureOwnedAlertRule {
    <#
    .SYNOPSIS
        Whether an analytics rule is provably the dependency fixture's.

    .DESCRIPTION
        Analytics rules have no ARM tags, so either of two markers is
        enough: the rule's name is one of the recomputed fixture rule ids,
        which survives any edit to its display name, or its description
        carries the '[SacFixture:<marker>:' sentinel. A rule made from a
        Content Hub template is never the fixture's.

    .PARAMETER AlertRule
        The rule.

    .PARAMETER FixtureMarker
        The marker.

    .PARAMETER ExpectedRuleId
        The fixture's rule ids.

    .OUTPUTS
        [bool]

    .EXAMPLE
        Test-iSOCFixtureOwnedAlertRule -AlertRule $rule -FixtureMarker $marker -ExpectedRuleId $ids
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowNull()]
        [object] $AlertRule,

        [Parameter(Mandatory)]
        [string] $FixtureMarker,

        [AllowEmptyCollection()]
        [AllowNull()]
        [string[]] $ExpectedRuleId
    )

    if ($null -eq $AlertRule) { return $false }
    if (-not [string]::IsNullOrWhiteSpace([string](Get-iSOCPropertyValue -InputObject $AlertRule -Path 'properties.alertRuleTemplateName'))) { return $false }

    $name = [string](Get-iSOCPropertyValue -InputObject $AlertRule -Path 'name')
    if ($name -and $ExpectedRuleId) {
        foreach ($expected in $ExpectedRuleId) {
            if ([string]::Equals($name, $expected, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
        }
    }

    $description = [string](Get-iSOCPropertyValue -InputObject $AlertRule -Path 'properties.description')
    if ($description) { return $description.Contains("[$((Get-iSOCDependencyFixtureSetting).FixtureTagName):${FixtureMarker}:") }
    $false
}

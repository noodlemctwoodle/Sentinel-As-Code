#Requires -Version 7.6

<#
.SYNOPSIS
    Whether a saved search carries the dependency fixture's ownership tag.

.DESCRIPTION
    By tag, not prefix: a customer object sharing the prefix survives, and a
    renamed fixture object is still known.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/Rehearsal/Test-iSOCFixtureOwnedSavedSearch.ps1
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

function Test-iSOCFixtureOwnedSavedSearch {
    <#
    .SYNOPSIS
        Whether a saved search carries the dependency fixture's ownership
        tag.

    .DESCRIPTION
        By the SacFixture tag, not the prefix, so a customer object that
        happens to share the prefix survives a removal, and a fixture object
        renamed by hand is still known.

    .PARAMETER SavedSearch
        The saved search.

    .PARAMETER FixtureMarker
        The marker the tag must hold.

    .OUTPUTS
        [bool]

    .EXAMPLE
        Test-iSOCFixtureOwnedSavedSearch -SavedSearch $search -FixtureMarker ClassicToDcr-DependencyFixture
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowNull()]
        [object] $SavedSearch,

        [Parameter(Mandatory)]
        [string] $FixtureMarker
    )

    $value = Get-iSOCSavedSearchTagValue -SavedSearch $SavedSearch -TagName (Get-iSOCDependencyFixtureSetting).FixtureTagName
    if ([string]::IsNullOrWhiteSpace($value)) { return $false }
    [string]::Equals($value, $FixtureMarker, [System.StringComparison]::OrdinalIgnoreCase)
}

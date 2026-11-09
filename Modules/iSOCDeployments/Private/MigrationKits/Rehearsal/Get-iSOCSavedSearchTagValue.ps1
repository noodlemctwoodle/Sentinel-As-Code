#Requires -Version 7.6

<#
.SYNOPSIS
    Read one tag from a saved search, as ARM returns it.

.DESCRIPTION
    properties.tags is a list of name and value pairs that survives a GET: the
    one ownership marker a saved search can carry.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/Rehearsal/Get-iSOCSavedSearchTagValue.ps1
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

function Get-iSOCSavedSearchTagValue {
    <#
    .SYNOPSIS
        Read one tag from a saved search, as ARM returns it.

    .DESCRIPTION
        properties.tags is a list of name and value pairs that survives a
        GET, so it is the ownership marker a saved search can carry. The tag
        name is matched without case; a missing tag is nothing.

    .PARAMETER SavedSearch
        The saved search.

    .PARAMETER TagName
        The tag.

    .OUTPUTS
        [string]

    .EXAMPLE
        Get-iSOCSavedSearchTagValue -SavedSearch $search -TagName SacFixture
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [object] $SavedSearch,

        [Parameter(Mandatory)]
        [string] $TagName
    )

    $tags = Get-iSOCPropertyValue -InputObject $SavedSearch -Path 'properties.tags'
    foreach ($tag in @($tags)) {
        if ($null -eq $tag) { continue }
        $nameMember = $tag.PSObject.Properties['name']
        $valueMember = $tag.PSObject.Properties['value']
        if ($nameMember -and $valueMember -and [string]::Equals([string]$nameMember.Value, $TagName, [System.StringComparison]::OrdinalIgnoreCase)) {
            return [string]$valueMember.Value
        }
    }
    $null
}

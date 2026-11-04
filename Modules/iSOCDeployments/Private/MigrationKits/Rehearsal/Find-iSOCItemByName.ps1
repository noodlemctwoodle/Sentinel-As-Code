#Requires -Version 7.2

<#
.SYNOPSIS
    Find an item in an ARM collection by its name, or by the last segment of its id.

.DESCRIPTION
    Matched without case; an item without a name is matched by its id, so a
    collision is not missed.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/Rehearsal/Find-iSOCItemByName.ps1
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

function Find-iSOCItemByName {
    <#
    .SYNOPSIS
        Find an item in an ARM collection by its name, or by the last
        segment of its id.

    .DESCRIPTION
        Microsoft's saved search samples carry only id, etag and properties,
        so an item without a name is matched by its id's last segment;
        missing it would let a PUT with etag '*' overwrite someone's parser.
        Matched without case.

    .PARAMETER Collection
        The items.

    .PARAMETER Name
        The name.

    .OUTPUTS
        [object] The first match, or nothing.

    .EXAMPLE
        Find-iSOCItemByName -Collection $saved -Name SacDep-OneHopParser
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [AllowEmptyCollection()]
        [AllowNull()]
        [object[]] $Collection,

        [Parameter(Mandatory)]
        [string] $Name
    )

    foreach ($item in @($Collection)) {
        if ($null -eq $item) { continue }
        $itemName = [string](Get-iSOCPropertyValue -InputObject $item -Path 'name')
        if (-not $itemName) {
            $id = [string](Get-iSOCPropertyValue -InputObject $item -Path 'id')
            if ($id) { $itemName = ($id -split '/')[-1] }
        }
        if ($itemName -and [string]::Equals($itemName, $Name, [System.StringComparison]::OrdinalIgnoreCase)) { return $item }
    }
    $null
}

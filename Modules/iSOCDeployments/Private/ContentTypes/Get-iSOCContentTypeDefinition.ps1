#Requires -Version 7.2

<#
.SYNOPSIS
    Look up content types by name.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/Get-iSOCContentTypeDefinition.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-23
    Version:      0.1.0
    Last Updated: 2026-10-23
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCContentTypeDefinition {
    <#
    .SYNOPSIS
        Return the registered types with the names given, in deploy order.

    .DESCRIPTION
        Names are matched without regard to case and may use wildcards. A
        name that matches no type throws with the names that exist, so a
        typo in -ContentType never quietly does nothing.

    .PARAMETER Name
        Type names or wildcard patterns. Without it every type is returned.

    .OUTPUTS
        [pscustomobject] iSOCDeployments.ContentType objects.

    .EXAMPLE
        Get-iSOCContentTypeDefinition -Name AnalyticsRule
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string[]] $Name
    )

    $all = @(Get-iSOCContentTypeRegistry)
    if (-not $Name) { return $all }

    foreach ($pattern in $Name) {
        if (-not @($all | Where-Object { $_.Name -like $pattern }).Count) {
            throw "No content type matches '$pattern'. Content types: $(($all | ForEach-Object Name) -join ', ')."
        }
    }
    $all | Where-Object {
        $typeName = $_.Name
        @($Name | Where-Object { $typeName -like $_ }).Count -gt 0
    }
}

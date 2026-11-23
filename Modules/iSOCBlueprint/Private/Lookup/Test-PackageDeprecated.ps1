#Requires -Version 7.6

<#
.SYNOPSIS
    Whether a Content Hub package is deprecated (properties.isDeprecated, a boolean or the string...

.DESCRIPTION
    One of the helpers beside Get-TemplateSolution.ps1, which describes the whole.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Lookup/Test-PackageDeprecated.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-13
    Version:      0.1.0
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Test-PackageDeprecated {
    <#
    .SYNOPSIS
        Whether a Content Hub package is deprecated (properties.isDeprecated,
        a boolean or the string "true").

    .PARAMETER Package
        One package as contentPackages or contentProductPackages returns it.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([AllowNull()] $Package)

    if (-not $Package -or -not $Package.properties -or $Package.properties.PSObject.Properties.Name -notcontains 'isDeprecated') { return $false }
    return ([string]$Package.properties.isDeprecated -eq 'true')
}

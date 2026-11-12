#Requires -Version 7.6

<#
.SYNOPSIS
    Count criteria per NIST CSF 2.0 function and per referenced subcategory.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Maturity/Reporting/Get-MaturityCsfRollup.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, Maturity Engine
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function Get-MaturityCsfRollup {
    <#
    .SYNOPSIS
        The NIST CSF 2.0 rollup of the resolved criteria.

    .PARAMETER Document
        The parsed maturity-criteria.json, which names the CSF functions and
        subcategories.

    .PARAMETER Criteria
        Every resolved criterion across the areas.

    .OUTPUTS
        One [pscustomobject] with Functions and Subcategories.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)] $Document,
        [Parameter(Mandatory = $true)] [AllowEmptyCollection()] [object[]] $Criteria
    )

    $functions = @(foreach ($fn in $Document.csf.functions.PSObject.Properties) {
        $hits = @($Criteria | Where-Object { @($_.csf | Where-Object { $_ -like "$($fn.Name).*" }).Count -gt 0 })
        [pscustomobject]@{
            id       = $fn.Name
            name     = [string]$fn.Value
            criteria = $hits.Count
            met      = @($hits | Where-Object status -eq 'Met').Count
            gap      = @($hits | Where-Object status -eq 'Gap').Count
            unknown  = @($hits | Where-Object status -eq 'Unknown').Count
        }
    })
    $usedIds = @($Criteria | ForEach-Object { $_.csf } | Sort-Object -Unique)
    $subcategories = @(foreach ($id in $usedIds) {
        $hits = @($Criteria | Where-Object { $_.csf -contains $id })
        [pscustomobject]@{
            id          = $id
            function    = $id.Substring(0, 2)
            # Subcategory ids contain a dot, so read the member directly
            # rather than through the dotted-path helper.
            outcome     = [string]$Document.csf.subcategories.PSObject.Properties[$id].Value
            met         = @($hits | Where-Object status -eq 'Met').Count
            gap         = @($hits | Where-Object status -eq 'Gap').Count
            unknown     = @($hits | Where-Object status -eq 'Unknown').Count
            criteriaIds = @($hits | ForEach-Object id)
        }
    })
    return [pscustomobject]@{ Functions = $functions; Subcategories = $subcategories }
}

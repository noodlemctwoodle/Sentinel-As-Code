#Requires -Version 7.6

<#
.SYNOPSIS
    Reads a property from an object, returning $null when it is absent.

.NOTES
    File:         Content/Workbooks/SentinelDataLake/SdlMigrationExport/Private/Azure/Get-SdlPropertyValue.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.2.0
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    Defines one function, dot-sourced by Export-SdlMigrationWorkbook.ps1
    (deprecated; to be replaced by the iSOCDeployments module).
#>

# Keeps the file help above from being read as the help of the function below.

function Get-SdlPropertyValue {
    <#
    .SYNOPSIS
        Reads a property from an object, returning $null when it is
        absent.

    .DESCRIPTION
        ARM responses omit properties such as schema.tableSubType on
        Microsoft tables. Reading them directly throws under
        Set-StrictMode, so every optional ARM property is read through
        this function.

    .PARAMETER Name
        The property name.

    .PARAMETER InputObject
        The object to read from. $null is allowed and returns $null.

    .OUTPUTS
        The property value, or $null.
    #>
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([object])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter()]
        [AllowNull()]
        [object]$InputObject
    )

    if ($null -eq $InputObject) {
        return $null
    }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($property) {
        return $property.Value
    }
    return $null
}

#Requires -Version 7.2

<#
.SYNOPSIS
    Reads the workspace functions (saved searches with a function alias).

.NOTES
    File:         Content/Workbooks/SentinelDataLake/SdlMigrationExport/Private/Inventory/Get-SdlFunctionInventory.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.2.0
    Last Updated: 2026-11-16
    Requires:     PowerShell 7.2+

    Defines one function, dot-sourced by Export-SdlMigrationWorkbook.ps1
    (deprecated; to be replaced by the iSOCDeployments module).
#>

# Keeps the file help above from being read as the help of the function below.

function Get-SdlFunctionInventory {
    <#
    .SYNOPSIS
        Reads the workspace functions (saved searches with a function
        alias).

    .DESCRIPTION
        Lists the saved searches and keeps those that carry a
        functionAlias, which are the KQL functions and parsers rules
        can call.

    .PARAMETER Connection
        The connection object.

    .OUTPUTS
        [pscustomobject] One row per function.
    #>
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)]
        [object]$Connection
    )

    $path = "$(Get-SdlBaseUri -Connection $Connection)/savedSearches?api-version=$($Connection.SavedSearchesApiVersion)"
    foreach ($search in @(Get-SdlArmList -Connection $Connection -Path $path)) {
        $properties = Get-SdlPropertyValue -InputObject $search -Name 'properties'
        $alias = Get-SdlPropertyValue -InputObject $properties -Name 'functionAlias'
        if (-not $alias) {
            continue
        }
        [pscustomobject]@{
            FunctionAlias      = $alias
            DisplayName        = Get-SdlPropertyValue -InputObject $properties -Name 'displayName'
            Category           = Get-SdlPropertyValue -InputObject $properties -Name 'category'
            FunctionParameters = Get-SdlPropertyValue -InputObject $properties -Name 'functionParameters'
            Version            = Get-SdlPropertyValue -InputObject $properties -Name 'version'
            QueryBody          = Get-SdlPropertyValue -InputObject $properties -Name 'query'
        }
    }
}

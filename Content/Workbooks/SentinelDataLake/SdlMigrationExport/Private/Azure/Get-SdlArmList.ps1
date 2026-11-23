#Requires -Version 7.6

<#
.SYNOPSIS
    Reads every page of an ARM list response.

.NOTES
    File:         Content/Workbooks/SentinelDataLake/SdlMigrationExport/Private/Azure/Get-SdlArmList.ps1
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

function Get-SdlArmList {
    <#
    .SYNOPSIS
        Reads every page of an ARM list response.

    .DESCRIPTION
        Follows nextLink until the list ends, so lists larger than one
        page are read in full rather than silently truncated. Callers
        wrap the call in @() so an empty list stays an empty array.

    .PARAMETER Connection
        The connection object.

    .PARAMETER Path
        Relative ARM list path including api-version.

    .OUTPUTS
        [object[]] Every item from every page.
    #>
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([object[]])]
    param (
        [Parameter(Mandatory)]
        [object]$Connection,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    $items = [System.Collections.Generic.List[object]]::new()
    $next = $Path
    while ($next) {
        $page = Invoke-SdlArmRequest -Connection $Connection -Path $next
        $value = Get-SdlPropertyValue -InputObject $page -Name 'value'
        if ($value) {
            $items.AddRange([object[]]@($value))
        }
        $next = Get-SdlPropertyValue -InputObject $page -Name 'nextLink'
    }
    return $items.ToArray()
}

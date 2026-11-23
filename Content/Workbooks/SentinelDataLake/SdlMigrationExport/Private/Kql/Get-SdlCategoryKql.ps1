#Requires -Version 7.6

<#
.SYNOPSIS
    Returns the KQL that assigns each table its category.

.NOTES
    File:         Content/Workbooks/SentinelDataLake/SdlMigrationExport/Private/Kql/Get-SdlCategoryKql.ps1
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

function Get-SdlCategoryKql {
    <#
    .SYNOPSIS
        Returns the KQL that assigns each table its category.

    .DESCRIPTION
        Adds Category and NotEligibleForLake columns from the lets of
        Get-SdlClassificationLet. Shared by every cost query.

    .OUTPUTS
        [string] The KQL pipeline fragment.
    #>
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([string])]
    param ()

    return @'
| extend Category = case(
    DataType in (notSupportedInLake), 'Not supported in Lake',
    DataType in (uebaTables), 'UEBA (Analytics-only)',
    DataType in (sentinelFeatureTables), 'Sentinel feature dependency',
    DataType in (systemTables), 'System table',
    DataType in (classicV1Tables), 'Custom log V1 (not supported)',
    DataType in (auxiliaryPlanTables), 'Auxiliary plan (not modelled)',
    DataType in (basicPlanTables), 'Basic plan (convert first)',
    DataType endswith '_CL', 'Custom log DCR-based',
    'Supported')
| extend NotEligibleForLake = Category in ('Not supported in Lake','UEBA (Analytics-only)','Sentinel feature dependency','System table','Custom log V1 (not supported)','Auxiliary plan (not modelled)','Basic plan (convert first)')

'@
}

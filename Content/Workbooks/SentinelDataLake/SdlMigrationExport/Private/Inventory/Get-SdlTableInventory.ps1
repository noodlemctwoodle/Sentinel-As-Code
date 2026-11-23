#Requires -Version 7.6

<#
.SYNOPSIS
    Reads the workspace tables and sorts them into the sets the
    classification needs.

.NOTES
    File:         Content/Workbooks/SentinelDataLake/SdlMigrationExport/Private/Inventory/Get-SdlTableInventory.ps1
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

function Get-SdlTableInventory {
    <#
    .SYNOPSIS
        Reads the workspace tables and sorts them into the sets the
        classification needs.

    .DESCRIPTION
        Lists every table through the Tables API and returns the
        Classic V1 custom tables, the DCR-based custom tables, and the
        Basic-plan and Auxiliary-plan tables.

    .PARAMETER Connection
        The connection object.

    .OUTPUTS
        [pscustomobject] TableCount, ClassicV1, DcrCustom, BasicPlan
        and AuxiliaryPlan.
    #>
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)]
        [object]$Connection
    )

    $path = "$(Get-SdlBaseUri -Connection $Connection)/tables?api-version=$($Connection.TablesApiVersion)"
    $tables = foreach ($table in @(Get-SdlArmList -Connection $Connection -Path $path)) {
        $properties = Get-SdlPropertyValue -InputObject $table -Name 'properties'
        $schema = Get-SdlPropertyValue -InputObject $properties -Name 'schema'
        [pscustomobject]@{
            Name    = $table.name
            SubType = Get-SdlPropertyValue -InputObject $schema -Name 'tableSubType'
            Plan    = Get-SdlPropertyValue -InputObject $properties -Name 'plan'
        }
    }
    $tables = @($tables)

    [pscustomobject]@{
        TableCount    = $tables.Count
        ClassicV1     = @($tables | Where-Object -FilterScript { $_.SubType -eq 'Classic' -and $_.Name -like '*_CL' } | ForEach-Object -Process { $_.Name })
        DcrCustom     = @($tables | Where-Object -FilterScript { $_.SubType -eq 'DataCollectionRuleBased' -and $_.Name -like '*_CL' } | ForEach-Object -Process { $_.Name })
        BasicPlan     = @($tables | Where-Object -FilterScript { $_.Plan -eq 'Basic' } | ForEach-Object -Process { $_.Name })
        AuxiliaryPlan = @($tables | Where-Object -FilterScript { $_.Plan -eq 'Auxiliary' } | ForEach-Object -Process { $_.Name })
    }
}

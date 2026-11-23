#Requires -Version 7.6

<#
.SYNOPSIS
    The names of the workspace's tables whose sub type is Classic, sorted.

.DESCRIPTION
    Platform tables that report Classic (AzureDiagnostics with Custom Fields)
    are included here; the caller keeps only _CL ones.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/ClassicToDcr/Get-iSOCClassicTableName.ps1
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

function Get-iSOCClassicTableName {
    <#
    .SYNOPSIS
        The names of the workspace's tables whose sub type is Classic,
        sorted.

    .DESCRIPTION
        A table reports Classic when it is a classic custom log, but also
        when Custom Fields were made against it, as with AzureDiagnostics;
        the caller keeps only the _CL names.

    .PARAMETER Context
        The workspace context.

    .OUTPUTS
        [string[]]

    .EXAMPLE
        Get-iSOCClassicTableName -Context $ctx
    #>
    [CmdletBinding()]
    [OutputType([string[]], [array])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Context
    )

    $tables = @(Invoke-iSOCRestRequest -Method GET -Path "$($Context.WorkspaceResourceId)/tables" -ApiVersion (Get-iSOCApiVersion OperationalInsights))
    $names = foreach ($table in $tables) {
        if ([string](Get-iSOCPropertyValue -InputObject $table -Path 'properties.schema.tableSubType') -eq 'Classic') {
            [string](Get-iSOCPropertyValue -InputObject $table -Path 'name')
        }
    }
    @($names | Sort-Object)
}

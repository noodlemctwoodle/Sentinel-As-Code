#Requires -Version 7.2

<#
.SYNOPSIS
    Read a workspace table's name, sub type and columns, or nothing when it does not exist.

.DESCRIPTION
    Not found is the expected answer for a table about to be made; any other
    failure is thrown.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/DcrFromSchema/Get-iSOCWorkspaceTableSchema.ps1
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

function Get-iSOCWorkspaceTableSchema {
    <#
    .SYNOPSIS
        Read a workspace table's name, sub type and columns, or nothing when
        it does not exist.

    .DESCRIPTION
        GETs the table at the TablePlans api-version (2025-07-01, as the
        table is written at). A 404 returns nothing; any other failure, or
        an answer without properties or properties.schema, is thrown with
        the start of the answer, so the caller can say why the read was
        lost. The sub type is Any when the answer gives none.

    .PARAMETER Context
        The workspace context.

    .PARAMETER Table
        The table name.

    .OUTPUTS
        [pscustomobject] Name, SubType and Columns; or nothing.

    .EXAMPLE
        Get-iSOCWorkspaceTableSchema -Context $ctx -Table 'MyApp_CL'
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Context,

        [Parameter(Mandatory)]
        [string] $Table
    )

    $body = Invoke-iSOCRestRequest -Method GET -Path "$($Context.WorkspaceResourceId)/tables/$Table" -ApiVersion (Get-iSOCApiVersion TablePlans) -Context $Context -AllowNotFound
    if ($null -eq $body) { return $null }

    $text = ConvertTo-Json -InputObject $body -Depth 10 -Compress
    if ($text.Length -gt 600) { $text = $text.Substring(0, 600) + '...' }

    $propertiesProperty = $body.PSObject.Properties['properties']
    if (-not $propertiesProperty -or -not $propertiesProperty.Value) {
        throw "Unexpected response reading table '$Table': no 'properties' object. Body: $text"
    }
    $schemaProperty = $propertiesProperty.Value.PSObject.Properties['schema']
    if (-not $schemaProperty -or -not $schemaProperty.Value) {
        throw "Unexpected response reading table '$Table': no 'properties.schema' object. Body: $text"
    }

    $schema = $schemaProperty.Value
    $columns = if ($schema.PSObject.Properties['columns'] -and $schema.PSObject.Properties['columns'].Value) { @($schema.PSObject.Properties['columns'].Value) } else { @() }
    $subType = if ($schema.PSObject.Properties['tableSubType'] -and $schema.PSObject.Properties['tableSubType'].Value) { [string]$schema.PSObject.Properties['tableSubType'].Value } else { 'Any' }
    $name = if ($schema.PSObject.Properties['name'] -and $schema.PSObject.Properties['name'].Value) { [string]$schema.PSObject.Properties['name'].Value } else { $Table }

    [pscustomobject]@{
        Name    = $name
        SubType = $subType
        Columns = $columns
    }
}

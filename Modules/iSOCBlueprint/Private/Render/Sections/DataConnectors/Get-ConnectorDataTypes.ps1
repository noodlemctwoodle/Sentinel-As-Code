#Requires -Version 7.6

<#
.SYNOPSIS
    Return a connector's data types.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/DataConnectors/Get-ConnectorDataTypes.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-ConnectorDataTypes {
    <#
    .SYNOPSIS
        Return a connector's data types.

    .DESCRIPTION
        RestApiPoller and Push connectors carry a single data type string in
        properties.dataType. Other kinds list the names in the properties.dataTypes
        map, joined with a comma and a space. An empty string is returned when there
        are none.

    .PARAMETER Connector
        The data connector resource.

    .OUTPUTS
        [string].
    #>
    [CmdletBinding()]
    param([psobject]$Connector)
    # RestApiPoller / Push schema: single string at properties.dataType.
    if ($Connector.kind -in @('RestApiPoller', 'Push')) {
        if ($Connector.properties.PSObject.Properties.Name -contains 'dataType' -and $Connector.properties.dataType) {
            return [string]$Connector.properties.dataType
        }
        return ''
    }
    $dataTypes = $Connector.properties.dataTypes
    if ($null -eq $dataTypes) { return '' }
    @($dataTypes.PSObject.Properties.Name) -join ', '
}

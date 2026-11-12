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
    Version:      0.1.0
    Last Updated: 2026-11-12
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-ConnectorDataTypes {
    param([psobject]$Connector)
    # RestApiPoller / Push schema: single string at properties.dataType.
    if ($Connector.kind -in @('RestApiPoller','Push')) {
        if ($Connector.properties.PSObject.Properties.Name -contains 'dataType' -and $Connector.properties.dataType) {
            return [string]$Connector.properties.dataType
        }
        return ''
    }
    $dataTypes = $Connector.properties.dataTypes
    if ($null -eq $dataTypes) { return '' }
    @($dataTypes.PSObject.Properties.Name) -join ', '
}

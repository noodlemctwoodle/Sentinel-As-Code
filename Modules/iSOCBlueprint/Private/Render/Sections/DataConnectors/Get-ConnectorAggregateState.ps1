#Requires -Version 7.6

<#
.SYNOPSIS
    Roll a connector's data types up to one state.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/DataConnectors/Get-ConnectorAggregateState.ps1
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

function Get-ConnectorAggregateState {
    param([psobject]$Connector)
    # RestApiPoller / Push connectors don't carry a dataTypes map. Treat the
    # presence of a dataType + dcrConfig as 'enabled' for that kind.
    if ($Connector.kind -in @('RestApiPoller','Push')) {
        $hasDataType = $Connector.properties.PSObject.Properties.Name -contains 'dataType' -and $Connector.properties.dataType
        $hasDcr = $Connector.properties.PSObject.Properties.Name -contains 'dcrConfig' -and $Connector.properties.dcrConfig
        if ($hasDataType -and $hasDcr) { return 'enabled' }
        if ($hasDataType -or $hasDcr) { return 'partial' }
        return 'unknown'
    }
    $dataTypes = $Connector.properties.dataTypes
    if ($null -eq $dataTypes) { return 'unknown' }
    $names = @($dataTypes.PSObject.Properties.Name)
    if ($names.Count -eq 0) { return 'unknown' }
    $states = foreach ($n in $names) {
        $s = $dataTypes.$n.state
        if ($s) { $s.ToLowerInvariant() } else { 'unknown' }
    }
    $enabled  = @($states | Where-Object { $_ -eq 'enabled' }).Count
    $disabled = @($states | Where-Object { $_ -eq 'disabled' }).Count
    if ($enabled -eq $states.Count) { 'enabled' }
    elseif ($disabled -eq $states.Count) { 'disabled' }
    elseif ($enabled -gt 0) { 'partial' }
    else { 'unknown' }
}

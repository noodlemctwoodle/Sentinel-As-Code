#Requires -Version 7.6

<#
.SYNOPSIS
    The catalogue id of a data connector resource from the workspace

.DESCRIPTION
    Split from Get-ConnectorCatalogue.ps1 so each file holds one function.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Lookup/Get-WorkspaceConnectorId.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-13
    Version:      0.1.0
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-WorkspaceConnectorId {
    <#
    .SYNOPSIS
        The catalogue id of a data connector resource from the workspace.

    .DESCRIPTION
        A codeless (CCF) connector's resource has a generic kind
        (RestApiPoller, GCP, Push) and names its connector definition, which
        is the catalogue id; any other connector's kind is the id.

    .PARAMETER Connector
        One entry from data-connectors-classic.json.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [AllowNull()] $Connector)

    if ($null -eq $Connector) { return '' }
    $props = if ($Connector.PSObject.Properties['properties']) { $Connector.properties } else { $null }
    if ($props -and $props.PSObject.Properties['connectorDefinitionName'] -and $props.connectorDefinitionName) {
        return [string]$props.connectorDefinitionName
    }
    if ($Connector.PSObject.Properties['kind']) { return [string]$Connector.kind }
    return ''
}

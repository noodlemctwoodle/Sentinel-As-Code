#Requires -Version 7.6

<#
.SYNOPSIS
    Return the display title of a connector.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/DataConnectors/Get-ConnectorFriendlyTitle.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.2
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

# Section: 10-data-connectors
# ---------------------------------------------------------------------------
# Classic connector resources are named by GUID and store per-data-type state
# under properties.dataTypes.<typename>.state. The earlier rendering pulled
# Name=$_.name (GUID) and State=$_.properties.connectorUiConfig.connectivityCriterias
# — a CCF field that doesn't exist on the classic schema, so State was always
# blank. The fix below maps Kind to a friendly Title, aggregates per-data-type
# state into a single overall state column, and lists the data-type names in
# their own column.
function Get-ConnectorFriendlyTitle {
    <#
    .SYNOPSIS
        Return the display title of a connector.

    .DESCRIPTION
        Kinds with a known product name return it. GenericUI and StaticUI return the
        connector UI title, or the kind when it has none. RestApiPoller and Push
        look up the connectorDefinitionName in CcfTitleByName and return the title
        followed by the kind in brackets, the definition name itself when it has no
        title, or the kind when it has no definition name. Any other kind is
        returned as it is.

    .PARAMETER Kind
        The connector kind.

    .PARAMETER Connector
        The connector resource. It is read for the UI title and the definition name.

    .PARAMETER CcfTitleByName
        A map of CCF definition name to title. Defaults to an empty map.

    .OUTPUTS
        [string].
    #>
    [CmdletBinding()]
    param([string]$Kind, [psobject]$Connector, [hashtable]$CcfTitleByName = @{})
    switch ($Kind) {
        'AzureActiveDirectory'                         { 'Microsoft Entra ID' }
        'MicrosoftCloudAppSecurity'                    { 'Microsoft Defender for Cloud Apps' }
        'MicrosoftDefenderAdvancedThreatProtection'    { 'Microsoft Defender for Endpoint' }
        'MicrosoftPurviewInformationProtection'        { 'Microsoft Purview Information Protection' }
        'MicrosoftThreatIntelligence'                  { 'Microsoft Defender Threat Intelligence' }
        'MicrosoftThreatProtection'                    { 'Microsoft Defender XDR' }
        'Office365'                                    { 'Microsoft 365 (Office 365)' }
        'AzureSecurityCenter'                          { 'Microsoft Defender for Cloud' }
        'GenericUI'                                    {
            if ($Connector.properties.connectorUiConfig.title) { $Connector.properties.connectorUiConfig.title } else { $Kind }
        }
        'StaticUI'                                     {
            if ($Connector.properties.connectorUiConfig.title) { $Connector.properties.connectorUiConfig.title } else { $Kind }
        }
        { $_ -in 'RestApiPoller','Push' }              {
            # CCF-derived kinds. Each connector instance carries a
            # connectorDefinitionName that points at the matching CCF
            # definition entry, where the human-readable title lives.
            $defName = $Connector.properties.connectorDefinitionName
            if ($defName -and $CcfTitleByName.ContainsKey($defName)) {
                "$($CcfTitleByName[$defName])  ($Kind)"
            } elseif ($defName) {
                "$defName  ($Kind)"
            } else {
                $Kind
            }
        }
        default                                        { $Kind }
    }
}

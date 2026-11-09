#Requires -Version 7.6

<#
.SYNOPSIS
    What each of a workflow's API connections is.

.DESCRIPTION
    Copied from Get-ConnectionMap (847ef86:Tools/Export-Playbooks.ps1).

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/Playbook/Get-iSOCPlaybookConnectionMap.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCPlaybookConnectionMap {
    <#
    .SYNOPSIS
        Describe each entry of a workflow's $connections parameter value.

    .DESCRIPTION
        Keyed by the reference name the workflow uses (azuresentinel,
        office365-1). Each entry has the managed API's name (from its id,
        else the reference name less the portal's numeric suffix), its
        display name, whether the live connection authenticates with the
        workflow's managed identity, and the connection resource's name
        prefix and ARM variable name. Only an API the workflow connects to
        more than once is indexed (Office3650, Office3651), so each
        resource name stays unique.

    .PARAMETER ConnectionsValue
        The value of the workflow's $connections parameter.

    .OUTPUTS
        [System.Collections.Specialized.OrderedDictionary] One entry per
        connection.

    .EXAMPLE
        $map = Get-iSOCPlaybookConnectionMap -ConnectionsValue $app.properties.parameters.'$connections'.value
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [AllowNull()]
        [object] $ConnectionsValue
    )

    $map = [ordered]@{}
    foreach ($entry in @(Get-iSOCPropertyEntry -InputObject $ConnectionsValue)) {
        $connName = $entry.Name
        $detail = $entry.Value
        $apiId = if ($detail -is [string]) { $detail } else { Get-iSOCPropertyValue -InputObject $detail -Path 'id' }
        $apiName = if ($apiId -and $apiId -match '/managedApis/([^/]+)$') { $Matches[1] } else { $connName -replace '[-_]\d+$', '' }
        $authType = if ($detail -is [string]) { $null } else { Get-iSOCPropertyValue -InputObject $detail -Path 'connectionProperties.authentication.type' }
        $map[$connName] = [ordered]@{
            ApiName             = $apiName
            DisplayName         = Get-iSOCApiConnectorDisplayName -ApiName $apiName
            UsesManagedIdentity = ($authType -eq 'ManagedServiceIdentity')
        }
    }

    $totals = @{}
    foreach ($conn in $map.Values) { $totals[$conn.DisplayName] = 1 + [int]$totals[$conn.DisplayName] }
    $indexes = @{}
    foreach ($conn in $map.Values) {
        $prefix = $conn.DisplayName
        if ($totals[$prefix] -gt 1) {
            $index = [int]$indexes[$prefix]
            $indexes[$prefix] = $index + 1
            $prefix = "$prefix$index"
        }
        $conn['ResourcePrefix'] = $prefix
        $conn['VariableName'] = "${prefix}ConnectionName"
    }
    $map
}

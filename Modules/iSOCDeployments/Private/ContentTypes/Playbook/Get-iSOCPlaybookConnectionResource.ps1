#Requires -Version 7.2

<#
.SYNOPSIS
    The Microsoft.Web/connections resources of an exported playbook.

.DESCRIPTION
    Copied from Build-ConnectionResources (847ef86:Tools/Export-Playbooks.ps1). The API version is the
    one the templates under Content/Playbooks/ use.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/Playbook/Get-iSOCPlaybookConnectionResource.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.0
    Last Updated: 2026-11-03
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCPlaybookConnectionResource {
    <#
    .SYNOPSIS
        Return one connection resource per connection.

    .DESCRIPTION
        A connection that authenticates with the workflow's managed identity
        keeps it (parameterValueType Alternative); an OAuth or API key
        connection is written without one and needs authorising once after
        deployment.

    .PARAMETER ConnectionMap
        From Get-iSOCPlaybookConnectionMap.

    .OUTPUTS
        [System.Collections.Specialized.OrderedDictionary] One resource each.

    .EXAMPLE
        Get-iSOCPlaybookConnectionResource -ConnectionMap $map
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $ConnectionMap
    )

    foreach ($conn in $ConnectionMap.Values) {
        $properties = [ordered]@{
            displayName           = "[variables('$($conn.VariableName)')]"
            customParameterValues = @{}
        }
        if ($conn.UsesManagedIdentity) { $properties['parameterValueType'] = 'Alternative' }
        $properties['api'] = [ordered]@{ id = Get-iSOCManagedApiIdExpression -ApiName $conn.ApiName }

        [ordered]@{
            type       = 'Microsoft.Web/connections'
            apiVersion = '2016-06-01'
            name       = "[variables('$($conn.VariableName)')]"
            location   = '[resourceGroup().location]'
            kind       = 'V1'
            properties = $properties
        }
    }
}

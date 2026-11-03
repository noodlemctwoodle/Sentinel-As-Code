#Requires -Version 7.2

<#
.SYNOPSIS
    The $connections value an exported playbook's workflow is given.

.DESCRIPTION
    Copied from Build-ConnectionParameters (847ef86:Tools/Export-Playbooks.ps1).

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/Playbook/Get-iSOCPlaybookConnectionParameter.ps1
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

function Get-iSOCPlaybookConnectionParameter {
    <#
    .SYNOPSIS
        Return the $connections value: each reference name pointing at its
        connection resource.

    .PARAMETER ConnectionMap
        From Get-iSOCPlaybookConnectionMap.

    .OUTPUTS
        [System.Collections.Specialized.OrderedDictionary] One entry per
        reference name.

    .EXAMPLE
        Get-iSOCPlaybookConnectionParameter -ConnectionMap $map
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $ConnectionMap
    )

    $values = [ordered]@{}
    foreach ($entry in $ConnectionMap.GetEnumerator()) {
        $conn = $entry.Value
        $value = [ordered]@{
            connectionId   = "[resourceId('Microsoft.Web/connections', variables('$($conn.VariableName)'))]"
            connectionName = "[variables('$($conn.VariableName)')]"
            id             = Get-iSOCManagedApiIdExpression -ApiName $conn.ApiName
        }
        if ($conn.UsesManagedIdentity) {
            $value['connectionProperties'] = [ordered]@{ authentication = [ordered]@{ type = 'ManagedServiceIdentity' } }
        }
        $values[$entry.Key] = $value
    }
    $values
}

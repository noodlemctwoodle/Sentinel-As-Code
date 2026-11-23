#Requires -Version 7.6

<#
.SYNOPSIS
    A copy of a definition with every string made portable.

.DESCRIPTION
    Copied from ConvertTo-PortableValue (847ef86:Tools/Export-Playbooks.ps1).

.NOTES
    File:         Modules/iSOCDeployments/Private/Export/ConvertTo-iSOCPortableValue.ps1
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

function ConvertTo-iSOCPortableValue {
    <#
    .SYNOPSIS
        Walk a value and return a copy with every string passed through
        ConvertTo-iSOCArmStringValue.

    .DESCRIPTION
        Objects and dictionaries become ordered dictionaries in the same
        key order, and lists stay lists (one item included). A string that
        is the whole value of a property naming a resource group
        (resourcegroup, resourcegroups, resourceGroupName) or the workspace
        (resourcename, workspaceName, workspace), as the Azure Monitor Logs
        connector's query fields do, becomes the parameter outright.

    .PARAMETER Value
        The value to walk.

    .PARAMETER Context
        From Get-iSOCPortableContext.

    .PARAMETER PropertyName
        The name of the property the value is in.

    .OUTPUTS
        The portable copy.

    .EXAMPLE
        $definition = ConvertTo-iSOCPortableValue -Value $app.properties.definition -Context $portable
    #>
    [CmdletBinding()]
    [OutputType([object], [System.Collections.Specialized.OrderedDictionary], [object[]], [string])]
    param(
        [AllowNull()]
        [object] $Value,

        [Parameter(Mandatory)]
        [hashtable] $Context,

        [string] $PropertyName
    )

    if ($null -eq $Value) { return $null }

    if ($Value -is [string]) {
        if ($PropertyName -match '^(resourcegroups?|resourceGroupName)$') {
            if ($Value -ieq $Context.WorkspaceResourceGroup) {
                [void]$Context.UsedParameters.Add('SentinelResourceGroupName')
                return "[parameters('SentinelResourceGroupName')]"
            }
            if ($Value -ieq $Context.PlaybookResourceGroup) {
                [void]$Context.UsedParameters.Add('AutomationResourceGroup')
                return "[parameters('AutomationResourceGroup')]"
            }
        }
        if ($PropertyName -match '^(resourcename|workspaceName|workspace)$' -and $Value -ieq $Context.WorkspaceName) {
            [void]$Context.UsedParameters.Add('SentinelWorkpaceName')
            return "[parameters('SentinelWorkpaceName')]"
        }
        return ConvertTo-iSOCArmStringValue -Value $Value -Context $Context
    }

    if ($Value -is [System.Collections.IDictionary]) {
        $out = [ordered]@{}
        foreach ($key in $Value.Keys) { $out[$key] = ConvertTo-iSOCPortableValue -Value $Value[$key] -Context $Context -PropertyName $key }
        return $out
    }

    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $out = [ordered]@{}
        foreach ($p in $Value.PSObject.Properties) { $out[$p.Name] = ConvertTo-iSOCPortableValue -Value $p.Value -Context $Context -PropertyName $p.Name }
        return $out
    }

    if ($Value -is [System.Collections.IEnumerable]) {
        $items = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $Value) { $items.Add((ConvertTo-iSOCPortableValue -Value $item -Context $Context -PropertyName $PropertyName)) }
        return , $items.ToArray()
    }

    $Value
}

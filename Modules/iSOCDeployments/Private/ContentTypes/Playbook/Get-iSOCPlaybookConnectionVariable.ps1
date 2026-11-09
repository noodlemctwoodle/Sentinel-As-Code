#Requires -Version 7.6

<#
.SYNOPSIS
    The template variables that name a playbook's connection resources.

.DESCRIPTION
    Copied from Build-ConnectionVariables (847ef86:Tools/Export-Playbooks.ps1).

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/Playbook/Get-iSOCPlaybookConnectionVariable.ps1
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

function Get-iSOCPlaybookConnectionVariable {
    <#
    .SYNOPSIS
        Return one variable per connection, named after the playbook:
        [concat('<prefix>-', parameters('PlaybookName'))].

    .PARAMETER ConnectionMap
        From Get-iSOCPlaybookConnectionMap.

    .OUTPUTS
        [System.Collections.Specialized.OrderedDictionary] The variables.

    .EXAMPLE
        Get-iSOCPlaybookConnectionVariable -ConnectionMap $map
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $ConnectionMap
    )

    $variables = [ordered]@{}
    foreach ($conn in $ConnectionMap.Values) {
        $variables[$conn.VariableName] = "[concat('$($conn.ResourcePrefix)-', parameters('PlaybookName'))]"
    }
    $variables
}

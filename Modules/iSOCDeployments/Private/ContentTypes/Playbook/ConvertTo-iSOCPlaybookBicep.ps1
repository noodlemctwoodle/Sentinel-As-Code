#Requires -Version 7.6

<#
.SYNOPSIS
    Write a playbook's ARM template as the repository's Bicep.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/Playbook/ConvertTo-iSOCPlaybookBicep.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-09
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function ConvertTo-iSOCPlaybookBicep {
    <#
    .SYNOPSIS
        Return the .bicep text of a playbook template, with the names and
        descriptions the repository's playbooks use.

    .DESCRIPTION
        The one path from a playbook template to Bicep: Export-iSOCContent
        (through ConvertTo-iSOCPlaybookFile) and Convert-iSOCPlaybook both
        come here, so an exported playbook and a converted one read alike.
        On top of ConvertTo-iSOCBicepTemplate:

        - each API connection's name variable is named after the managed
          API it connects to, from the connector's display name
          (Get-iSOCApiConnectorDisplayName) in lower camel case:
          microsoftSentinelConnectionName for azuresentinel, and so the
          connection is microsoftSentinelConnection. A second connection
          to the same API is microsoftSentinel2ConnectionName, and so on,
          in template order. A connection whose name is not a variable, or
          whose API cannot be read, keeps the writer's own name;
        - PlaybookName, and each parameter the deploy fills in
          (Get-iSOCPlaybookInjectedParameter), gets a description when the
          template has none for it.

        Only names and descriptions change, so the Bicep deploys what the
        template does.

    .PARAMETER Template
        The playbook's ARM template, as ConvertFrom-iSOCJsonText or
        ConvertTo-iSOCPlaybookTemplate gives it.

    .OUTPUTS
        [string] The Bicep file's text.

    .EXAMPLE
        ConvertTo-iSOCPlaybookBicep -Template (ConvertFrom-iSOCJsonText -Text (Get-Content $path -Raw))
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [object] $Template
    )

    $variableName = @{}
    $used = @{}
    # Assigned first: the reader returns the array whole, which @() would
    # wrap as one item.
    $resources = Get-iSOCPropertyValue -InputObject $Template -Path 'resources'
    foreach ($resource in $resources) {
        if ([string](Get-iSOCPropertyValue -InputObject $resource -Path 'type') -ine 'Microsoft.Web/connections') { continue }
        $name = [string](Get-iSOCPropertyValue -InputObject $resource -Path 'name')
        if ($name -notmatch "^\[variables\('([^']+)'\)\]$") { continue }
        $nameVariable = $Matches[1]
        if ($variableName.ContainsKey($nameVariable)) { continue }
        $apiId = [string](Get-iSOCPropertyValue -InputObject $resource -Path 'properties.api.id')
        $api = if ($apiId -match '/managedApis/([A-Za-z0-9_.-]+)') { $Matches[1] }
        elseif ($apiId -match "'managedApis'\s*,\s*[^,]+,\s*'([^']+)'") { $Matches[1] }
        else { $null }
        if (-not $api) { continue }
        $stem = ConvertTo-iSOCBicepCamelCase -Name (Get-iSOCApiConnectorDisplayName -ApiName $api)
        $used[$stem] = 1 + [int]$used[$stem]
        $number = if ($used[$stem] -gt 1) { [string]$used[$stem] } else { '' }
        $variableName[$nameVariable] = "$stem${number}ConnectionName"
    }

    $descriptions = @{ PlaybookName = "The Logic App's name." }
    foreach ($known in Get-iSOCPlaybookInjectedParameter) { $descriptions[$known.Name] = $known.Description }

    ConvertTo-iSOCBicepTemplate -Template $Template -VariableName $variableName -ParameterDescription $descriptions
}

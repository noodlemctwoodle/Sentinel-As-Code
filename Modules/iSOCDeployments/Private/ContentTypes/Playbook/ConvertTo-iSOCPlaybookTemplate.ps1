#Requires -Version 7.6

<#
.SYNOPSIS
    The ARM template a Logic App is exported as.

.DESCRIPTION
    Copied from Build-ArmTemplate (847ef86:Tools/Export-Playbooks.ps1). The workflow and connection API
    versions are the ones the templates under Content/Playbooks/ use.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/Playbook/ConvertTo-iSOCPlaybookTemplate.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.2.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function ConvertTo-iSOCPlaybookTemplate {
    <#
    .SYNOPSIS
        Return a parameterised ARM template for a Logic App, in the shape
        Content/Playbooks/ holds.

    .DESCRIPTION
        - Parameters: PlaybookName, its default the Logic App's live name,
          so a redeploy updates the same workflow; for Sentinel-triggered
          categories AutomationResourceGroup and SentinelWorkpaceName, as
          the existing templates have; and every other parameter an
          expression references.
        - The workflow, at Logic Apps 2019-05-01 (the newest api-version,
          and the one Bicep has types for): its definition made portable,
          its live state, the Source: Sentinel-As-Code tag
          Grant-iSOCPlaybookPermission keys off, a system-assigned
          identity, its connections, and for a module an empty access
          control block (only other Logic Apps may call it).
        - One Microsoft.Web/connections resource per connection, named
          after the playbook.
        - The metadata block the docs describe: title, description,
          lastUpdateTime (today, dd-MM-yyyy), entities, tags, support and
          author.

    .PARAMETER LogicApp
        The Logic App, with its definition.

    .PARAMETER Category
        From Get-iSOCPlaybookCategory.

    .PARAMETER PlaybookName
        The Logic App's name.

    .PARAMETER AuthorName
        The author written into the metadata.

    .PARAMETER Context
        From Get-iSOCPortableContext, fresh for this Logic App.

    .OUTPUTS
        [System.Collections.Specialized.OrderedDictionary] The template.

    .EXAMPLE
        $template = ConvertTo-iSOCPlaybookTemplate -LogicApp $app -Category Incident -PlaybookName $app.name -AuthorName 'noodlemctwoodle' -Context $portable
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [psobject] $LogicApp,

        [Parameter(Mandatory)]
        [string] $Category,

        [Parameter(Mandatory)]
        [string] $PlaybookName,

        [Parameter(Mandatory)]
        [string] $AuthorName,

        [Parameter(Mandatory)]
        [hashtable] $Context
    )

    $properties = Get-iSOCPropertyValue -InputObject $LogicApp -Path 'properties'
    $definition = Get-iSOCPropertyValue -InputObject $properties -Path 'definition'
    $connValues = Get-iSOCPropertyValue -InputObject $properties -Path 'parameters.$connections.value'

    $connectionMap = Get-iSOCPlaybookConnectionMap -ConnectionsValue $connValues
    $portableDefinition = ConvertTo-iSOCPortableValue -Value $definition -Context $Context

    $parameters = [ordered]@{ PlaybookName = [ordered]@{ defaultValue = $PlaybookName; type = 'string' } }
    $sentinelCategory = $Category -in @('Incident', 'Entity', 'Alert', 'Watchlist')
    foreach ($name in @('AutomationResourceGroup', 'SentinelWorkpaceName', 'SentinelResourceGroupName', 'WorkspaceId')) {
        $baseline = $sentinelCategory -and $name -in @('AutomationResourceGroup', 'SentinelWorkpaceName')
        if ($baseline -or $Context.UsedParameters.Contains($name)) { $parameters[$name] = [ordered]@{ defaultValue = ''; type = 'string' } }
    }

    $state = Get-iSOCPropertyValue -InputObject $properties -Path 'state'
    $workflowProperties = [ordered]@{
        provisioningState = 'Succeeded'
        state             = $(if ($state) { $state } else { 'Enabled' })
        definition        = $portableDefinition
    }
    if ($connectionMap.Count -gt 0) {
        $workflowProperties['parameters'] = [ordered]@{ '$connections' = [ordered]@{ value = Get-iSOCPlaybookConnectionParameter -ConnectionMap $connectionMap } }
    }
    if ($Category -eq 'Module') {
        $workflowProperties['accessControl'] = [ordered]@{
            triggers = [ordered]@{ allowedCallerIpAddresses = @() }
            actions  = [ordered]@{ allowedCallerIpAddresses = @() }
        }
    }

    $dependsOn = @($connectionMap.Values | ForEach-Object { "[resourceId('Microsoft.Web/connections', variables('$($_.VariableName)'))]" })
    $resources = [System.Collections.Generic.List[object]]::new()
    $resources.Add([ordered]@{
            properties = $workflowProperties
            name       = "[parameters('PlaybookName')]"
            type       = 'Microsoft.Logic/workflows'
            location   = '[resourceGroup().location]'
            tags       = [ordered]@{ Source = 'Sentinel-As-Code' }
            identity   = [ordered]@{ type = 'SystemAssigned' }
            apiVersion = '2019-05-01'
            dependsOn  = $dependsOn
        })
    foreach ($connectionResource in @(Get-iSOCPlaybookConnectionResource -ConnectionMap $connectionMap)) { $resources.Add($connectionResource) }

    $entities = @(Get-iSOCPlaybookEntity -Definition $definition)
    $description = Get-iSOCPlaybookDescription -LogicApp $LogicApp -Category $Category -PlaybookName $PlaybookName -Entities $entities

    [ordered]@{
        '$schema'      = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#'
        contentVersion = '1.0.0.0'
        metadata       = [ordered]@{
            title          = $PlaybookName
            description    = $description
            lastUpdateTime = (Get-Date -Format 'dd-MM-yyyy')
            entities       = $entities
            tags           = @($Category, 'Source: Sentinel-As-Code')
            support        = [ordered]@{ tier = 'community' }
            author         = [ordered]@{ name = $AuthorName }
        }
        parameters     = $parameters
        variables      = Get-iSOCPlaybookConnectionVariable -ConnectionMap $connectionMap
        resources      = $resources.ToArray()
    }
}

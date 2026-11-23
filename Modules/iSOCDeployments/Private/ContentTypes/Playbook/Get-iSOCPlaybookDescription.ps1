#Requires -Version 7.6

<#
.SYNOPSIS
    The description written into an exported playbook's metadata.

.DESCRIPTION
    Copied from Get-WorkflowDescription (847ef86:Tools/Export-Playbooks.ps1).

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/Playbook/Get-iSOCPlaybookDescription.ps1
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

function Get-iSOCPlaybookDescription {
    <#
    .SYNOPSIS
        Return a workflow's own description, or one made from its category
        and entities.

    .PARAMETER LogicApp
        The Logic App.

    .PARAMETER Category
        Its category, from Get-iSOCPlaybookCategory.

    .PARAMETER PlaybookName
        Its name.

    .PARAMETER Entities
        Its entity types, from Get-iSOCPlaybookEntity.

    .OUTPUTS
        [string] The description.

    .EXAMPLE
        Get-iSOCPlaybookDescription -LogicApp $app -Category Incident -PlaybookName $app.name
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [psobject] $LogicApp,

        [Parameter(Mandatory)]
        [string] $Category,

        [Parameter(Mandatory)]
        [string] $PlaybookName,

        [string[]] $Entities = @()
    )

    $desc = Get-iSOCPropertyValue -InputObject $LogicApp -Path 'properties.definition.description'
    if ($desc) { return [string]$desc }
    $desc = Get-iSOCPropertyValue -InputObject $LogicApp -Path 'properties.description'
    if ($desc) { return [string]$desc }

    $entitySuffix = ''
    if ($Entities.Count -gt 0) { $entitySuffix = " targeting $($Entities -join ', ') entities" }

    switch ($Category) {
        'Incident' { "Sentinel incident-trigger playbook for ${PlaybookName}${entitySuffix}." }
        'Entity' { "Sentinel entity-trigger playbook for ${PlaybookName}${entitySuffix}." }
        'Alert' { "Sentinel alert-trigger playbook for ${PlaybookName}${entitySuffix}." }
        'Module' { "Reusable automation module: ${PlaybookName}." }
        'Watchlist' { "Watchlist management playbook: ${PlaybookName}." }
        default { "Automation playbook: ${PlaybookName}." }
    }
}

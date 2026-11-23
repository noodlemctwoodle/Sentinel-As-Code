#Requires -Version 7.6

<#
.SYNOPSIS
    ToRequest handler for playbooks: the deployment deploy runs.

.DESCRIPTION
    Built as Deploy-CustomPlaybooks built it, apart from the deployment
    name, which Invoke-iSOCPlaybookDeploy adds. The parameters it fills in
    come from Get-iSOCPlaybookInjectedParameter, the list the Bicep
    playbooks' descriptions come from too.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/Playbook/ConvertTo-iSOCPlaybookRequest.ps1
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

function ConvertTo-iSOCPlaybookRequest {
    <#
    .SYNOPSIS
        Build the resource group deployment parameters for one template.

    .DESCRIPTION
        The template deploys to the playbook resource group, with its
        parameters file when one sits beside it. The template parameters
        the workspace can answer are filled in from the context, and only
        those the template declares: AutomationResourceGroup and
        PlaybookResourceGroup (the playbook resource group),
        SentinelResourceGroup and SentinelResourceGroupName (the workspace
        resource group), SentinelWorkspaceName and its common misspelling
        SentinelWorkpaceName, SubscriptionId, and WorkspaceId (the Log
        Analytics workspace id) when the context has it. The function
        deploys nothing.

    .PARAMETER Item
        A repository item from Read-iSOCPlaybookRepo that passed
        Test-iSOCPlaybook.

    .PARAMETER Context
        The workspace context.

    .OUTPUTS
        [pscustomobject] iSOCDeployments.Request: ContentType, Identity,
        ResourceName (the file name), Body (the deployment parameters, ready
        to splat) and Injected (the template parameters filled in).

    .EXAMPLE
        $request = ConvertTo-iSOCPlaybookRequest -Item $item -Context $context
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Item,

        [Parameter(Mandatory)]
        [psobject] $Context
    )

    $knownParams = @{}
    foreach ($known in Get-iSOCPlaybookInjectedParameter) {
        $value = $Context.($known.ContextProperty)
        if ($known.Optional -and -not $value) { continue }
        $knownParams[$known.Name] = $value
    }

    $deployParams = @{
        ResourceGroupName = $Context.PlaybookResourceGroup
        TemplateFile      = $Item.Path
    }
    if (Test-Path -LiteralPath $Item.ParametersPath -PathType Leaf) { $deployParams.TemplateParameterFile = $Item.ParametersPath }

    $injected = [System.Collections.Generic.List[string]]::new()
    $templateParams = Get-iSOCPropertyValue -InputObject $Item.Data -Path 'parameters'
    if ($templateParams) {
        foreach ($paramName in @($templateParams.PSObject.Properties | ForEach-Object { $_.Name })) {
            if ($knownParams.ContainsKey($paramName)) {
                $deployParams[$paramName] = $knownParams[$paramName]
                $injected.Add($paramName)
            }
        }
    }

    [pscustomobject]@{
        PSTypeName   = 'iSOCDeployments.Request'
        ContentType  = $Item.ContentType
        Identity     = $Item.Identity
        ResourceName = $Item.BaseName
        Body         = $deployParams
        Injected     = $injected.ToArray()
    }
}

#Requires -Version 7.6

<#
.SYNOPSIS
    ReadWorkspace handler for playbooks: the Logic Apps in the playbook
    resource group.

.DESCRIPTION
    Replaces the listing in Invoke-PlaybookExport (847ef86:Tools/Export-Playbooks.ps1).

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/Playbook/Read-iSOCPlaybookWorkspace.ps1
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

function Read-iSOCPlaybookWorkspace {
    <#
    .SYNOPSIS
        List the Logic Apps in the playbook resource group, every page,
        each with its workflow definition.

    .DESCRIPTION
        A Logic App the list returns without its definition is read on its
        own. One that cannot be read is returned as the list gave it, with
        the error in a ReadError property, so the export can say why it
        failed.

    .PARAMETER Context
        The workspace context; its PlaybookResourceGroup is listed.

    .PARAMETER ContentType
        The playbook content type.

    .OUTPUTS
        [psobject] The Logic Apps as the API returns them.

    .EXAMPLE
        $apps = @(Read-iSOCPlaybookWorkspace -Context $ctx -ContentType $type)
    #>
    [CmdletBinding()]
    [OutputType([psobject])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Context,

        [Parameter(Mandatory)]
        [psobject] $ContentType
    )

    $apiVersion = Get-iSOCApiVersion $ContentType.ApiVersion
    Write-iSOCLog 'Listing Logic Apps...'
    $apps = @(Invoke-iSOCRestRequest -Method GET -Path ((Get-iSOCResourcePath -Context $Context -ContentType $ContentType) + '?$top=100') -ApiVersion $apiVersion -Context $Context | Where-Object { $null -ne $_ })
    Write-iSOCLog "Found $($apps.Count) Logic App(s) in the playbook resource group."

    foreach ($app in $apps) {
        if (Get-iSOCPropertyValue -InputObject $app -Path 'properties.definition') {
            $app
            continue
        }
        try {
            $detail = Invoke-iSOCRestRequest -Method GET -Path ([string](Get-iSOCPropertyValue -InputObject $app -Path 'id')) -ApiVersion $apiVersion -Context $Context
            if ($null -ne $detail) { $detail } else { $app }
        }
        catch {
            $app | Add-Member -NotePropertyName ReadError -NotePropertyValue "could not be read: $($_.Exception.Message)" -Force
            $app
        }
    }
}

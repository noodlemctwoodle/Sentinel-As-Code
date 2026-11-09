#Requires -Version 7.6

<#
.SYNOPSIS
    The template parameters a playbook deploy fills in from the workspace.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/Playbook/Get-iSOCPlaybookInjectedParameter.ps1
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

function Get-iSOCPlaybookInjectedParameter {
    <#
    .SYNOPSIS
        Return each parameter the deploy fills in, with where its value
        comes from and how a Bicep playbook describes it.

    .DESCRIPTION
        The one list both sides read: ConvertTo-iSOCPlaybookRequest fills
        each parameter a template declares from the context property named
        here, and ConvertTo-iSOCPlaybookBicep gives the parameter this
        description, so the deploy and the files cannot disagree on the
        names. SentinelWorkpaceName keeps its misspelling: the templates
        that use it are matched by name.

    .OUTPUTS
        [pscustomobject] Name, ContextProperty, Optional (filled in only
        when the context has a value) and Description.

    .EXAMPLE
        Get-iSOCPlaybookInjectedParameter | Format-Table Name, ContextProperty
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $playbookGroup = 'The playbook resource group; the deploy fills it in.'
    $workspaceGroup = "The Sentinel workspace's resource group; the deploy fills it in."
    $workspaceName = "The Sentinel workspace's name; the deploy fills it in."
    $new = {
        param([string] $Name, [string] $ContextProperty, [bool] $Optional, [string] $Description)
        [pscustomobject]@{
            PSTypeName      = 'iSOCDeployments.PlaybookInjectedParameter'
            Name            = $Name
            ContextProperty = $ContextProperty
            Optional        = $Optional
            Description     = $Description
        }
    }
    & $new 'AutomationResourceGroup' 'PlaybookResourceGroup' $false $playbookGroup
    & $new 'PlaybookResourceGroup' 'PlaybookResourceGroup' $false $playbookGroup
    & $new 'SentinelResourceGroup' 'ResourceGroup' $false $workspaceGroup
    & $new 'SentinelResourceGroupName' 'ResourceGroup' $false $workspaceGroup
    & $new 'SentinelWorkpaceName' 'WorkspaceName' $false $workspaceName
    & $new 'SentinelWorkspaceName' 'WorkspaceName' $false $workspaceName
    & $new 'SubscriptionId' 'SubscriptionId' $false "The subscription's id; the deploy fills it in."
    & $new 'WorkspaceId' 'WorkspaceId' $true "The Log Analytics workspace's id; the deploy fills it in."
}

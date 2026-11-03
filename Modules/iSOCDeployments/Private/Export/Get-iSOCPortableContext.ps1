#Requires -Version 7.2

<#
.SYNOPSIS
    The rules that turn a workspace's own values into ARM expressions.

.DESCRIPTION
    Copied from Get-PortableContext (847ef86:Tools/Export-Playbooks.ps1).

.NOTES
    File:         Modules/iSOCDeployments/Private/Export/Get-iSOCPortableContext.ps1
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

function Get-iSOCPortableContext {
    <#
    .SYNOPSIS
        Build the replacement rules for making exported content portable.

    .DESCRIPTION
        GUIDs (the subscription id, the workspace id) are replaced wherever
        they appear. Resource group and workspace names are short and could
        be ordinary text, so they are replaced only in ARM path position
        (after resourceGroups/ or workspaces/, or inside the
        @{encodeURIComponent('...')} form connector paths use), or as the
        whole value of a property that names one (see
        ConvertTo-iSOCPortableValue). Rules are in priority order: where
        two match the same text the earlier wins, so a workflow reference
        resolves to AutomationResourceGroup even when the playbooks share
        the workspace's resource group. UsedParameters fills in as rules
        fire, so a template declares only the parameters it references.

    .PARAMETER SubscriptionId
        The subscription's id.

    .PARAMETER PlaybookResourceGroup
        The playbook resource group (AutomationResourceGroup).

    .PARAMETER WorkspaceResourceGroup
        The workspace's resource group (SentinelResourceGroupName).

    .PARAMETER WorkspaceName
        The workspace's name (SentinelWorkpaceName, the spelling the
        templates use).

    .PARAMETER WorkspaceId
        The workspace's id (WorkspaceId), when known.

    .OUTPUTS
        [hashtable] Rules, PlaybookResourceGroup, WorkspaceResourceGroup,
        WorkspaceName and UsedParameters.

    .EXAMPLE
        $portable = Get-iSOCPortableContext -SubscriptionId $ctx.SubscriptionId -PlaybookResourceGroup $ctx.PlaybookResourceGroup -WorkspaceResourceGroup $ctx.ResourceGroup -WorkspaceName $ctx.WorkspaceName -WorkspaceId $ctx.WorkspaceId
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $SubscriptionId,

        [Parameter(Mandatory)]
        [string] $PlaybookResourceGroup,

        [Parameter(Mandatory)]
        [string] $WorkspaceResourceGroup,

        [Parameter(Mandatory)]
        [string] $WorkspaceName,

        [string] $WorkspaceId
    )

    $wrap = "(?:@\{encodeURIComponent\(')?"
    $end = "(?=['/?&)\s]|$)"
    $sub = [regex]::Escape($SubscriptionId)
    $prg = [regex]::Escape($PlaybookResourceGroup)
    $wrg = [regex]::Escape($WorkspaceResourceGroup)
    $ws = [regex]::Escape($WorkspaceName)

    $rules = [System.Collections.Generic.List[hashtable]]::new()
    $rules.Add(@{ Pattern = "(?i)(?<v>$sub)"; Expression = 'subscription().subscriptionId'; Parameter = $null })
    if ($WorkspaceId) {
        $rules.Add(@{ Pattern = "(?i)(?<v>$([regex]::Escape($WorkspaceId)))"; Expression = "parameters('WorkspaceId')"; Parameter = 'WorkspaceId' })
    }
    $rules.Add(@{ Pattern = "(?i)resourceGroups/$wrap(?<v>$prg)(?=(?:'\)\})?/providers/Microsoft\.Logic/workflows/)"; Expression = "parameters('AutomationResourceGroup')"; Parameter = 'AutomationResourceGroup' })
    $rules.Add(@{ Pattern = "(?i)resourceGroups/$wrap(?<v>$wrg)$end"; Expression = "parameters('SentinelResourceGroupName')"; Parameter = 'SentinelResourceGroupName' })
    $rules.Add(@{ Pattern = "(?i)resourceGroups/$wrap(?<v>$prg)$end"; Expression = "parameters('AutomationResourceGroup')"; Parameter = 'AutomationResourceGroup' })
    $rules.Add(@{ Pattern = "(?i)workspaces/$wrap(?<v>$ws)$end"; Expression = "parameters('SentinelWorkpaceName')"; Parameter = 'SentinelWorkpaceName' })

    @{
        Rules                  = $rules.ToArray()
        PlaybookResourceGroup  = $PlaybookResourceGroup
        WorkspaceResourceGroup = $WorkspaceResourceGroup
        WorkspaceName          = $WorkspaceName
        UsedParameters         = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    }
}

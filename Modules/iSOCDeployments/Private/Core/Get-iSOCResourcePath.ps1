#Requires -Version 7.2

<#
.SYNOPSIS
    Build the request path for one item of a content type.

.NOTES
    File:         Modules/iSOCDeployments/Private/Core/Get-iSOCResourcePath.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-23
    Version:      0.1.0
    Last Updated: 2026-10-23
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCResourcePath {
    <#
    .SYNOPSIS
        Join a content type's scope, collection and an item name.

    .DESCRIPTION
        A content type names its scope (the workspace, the Sentinel resource
        group, the playbook resource group or the tenant) and the collection
        under it. The scope comes from the context, so the same definition
        works in any subscription and cloud. The result has no host and no
        api-version; Invoke-iSOCRestRequest adds both.

    .PARAMETER Context
        The workspace context.

    .PARAMETER ContentType
        The content type, from Get-iSOCContentTypeDefinition.

    .PARAMETER Name
        The item's resource name. Without it the collection path is returned.

    .OUTPUTS
        [string] The ARM path, or for a Graph type the path under the Graph
        version segment.

    .EXAMPLE
        Get-iSOCResourcePath -Context $ctx -ContentType $rules -Name $request.ResourceName
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Context,

        [Parameter(Mandatory)]
        [psobject] $ContentType,

        [string] $Name
    )

    $root = switch ($ContentType.Scope) {
        'Workspace' { $Context.WorkspaceResourceId }
        'ResourceGroup' { "/subscriptions/$($Context.SubscriptionId)/resourceGroups/$($Context.ResourceGroup)" }
        'PlaybookResourceGroup' { "/subscriptions/$($Context.SubscriptionId)/resourceGroups/$($Context.PlaybookResourceGroup)" }
        'Tenant' { '' }
        default { throw "Content type '$($ContentType.Name)' has an unknown scope '$($ContentType.Scope)'." }
    }

    $path = "$root$($ContentType.CollectionPath)"
    if ($Name) { $path = "$path/$Name" }
    $path
}

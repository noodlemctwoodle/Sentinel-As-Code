#Requires -Version 7.6

<#
.SYNOPSIS
    Build the workspace setting request body for one file.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/WorkspaceSetting/ConvertTo-iSOCWorkspaceSettingRequest.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function ConvertTo-iSOCWorkspaceSettingRequest {
    <#
    .SYNOPSIS
        Build the workspace setting request body for one file.

    .DESCRIPTION
        The setting's kind and its properties as the file has them, or an
        empty properties object when it has none (anomalies and EyesOn have
        nothing to set: the setting existing turns the feature on). The
        etag is not part of the request: it is the workspace's, and the
        Deploy handler adds the one it reads. The function reads nothing
        outside the item and sends nothing.

    .PARAMETER Item
        A repository item from Read-iSOCWorkspaceSettingRepo that passed
        Test-iSOCWorkspaceSetting.

    .OUTPUTS
        [pscustomobject] iSOCDeployments.Request: ContentType, Identity,
        ResourceName (the setting's name) and Body.

    .EXAMPLE
        $request = ConvertTo-iSOCWorkspaceSettingRequest -Item $item
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Item
    )

    $setting = $Item.Data
    $properties = [ordered]@{}
    $fromFile = Get-iSOCPropertyValue -InputObject $setting -Path 'properties'
    if ($null -ne $fromFile) {
        foreach ($property in $fromFile.PSObject.Properties) { $properties[$property.Name] = $property.Value }
    }

    [pscustomobject]@{
        PSTypeName   = 'iSOCDeployments.Request'
        ContentType  = $Item.ContentType
        Identity     = $Item.Identity
        ResourceName = [string]$setting.name
        Body         = [ordered]@{ kind = [string]$setting.kind; properties = $properties }
    }
}

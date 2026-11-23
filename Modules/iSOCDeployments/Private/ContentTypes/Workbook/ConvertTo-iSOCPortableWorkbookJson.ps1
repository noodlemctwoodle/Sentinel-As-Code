#Requires -Version 7.6

<#
.SYNOPSIS
    A workbook template with the workspace's resource id made a placeholder.

.DESCRIPTION
    Copied from Remove-WorkspaceArmId (Tools/Export-SentinelWorkbooks.ps1).

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/Workbook/ConvertTo-iSOCPortableWorkbookJson.ps1
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

function ConvertTo-iSOCPortableWorkbookJson {
    <#
    .SYNOPSIS
        Replace the workspace's resource id in a workbook template with the
        placeholder the repository's workbooks use.

    .DESCRIPTION
        A saved workbook names its workspace in fallbackResourceIds and
        sometimes in its queries. Every occurrence, in any case, becomes
        /subscriptions/00000000-0000-0000-0000-000000000000/resourcegroups/your-resource-group/providers/microsoft.operationalinsights/workspaces/your-workspace,
        so the template is not tied to one workspace. A workbook opened in
        its Sentinel workspace does not read the value.

    .PARAMETER Json
        The template as JSON text.

    .PARAMETER WorkspaceResourceId
        The workspace's resource id.

    .OUTPUTS
        [string] The JSON text.

    .EXAMPLE
        ConvertTo-iSOCPortableWorkbookJson -Json $json -WorkspaceResourceId $ctx.WorkspaceResourceId
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Json,

        [Parameter(Mandatory)]
        [string] $WorkspaceResourceId
    )

    $placeholder = '/subscriptions/00000000-0000-0000-0000-000000000000/resourcegroups/your-resource-group/providers/microsoft.operationalinsights/workspaces/your-workspace'
    [regex]::Replace($Json, [regex]::Escape($WorkspaceResourceId), $placeholder, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
}

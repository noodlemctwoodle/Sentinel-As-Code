#Requires -Version 7.6

<#
.SYNOPSIS
    Build the workbook and metadata bodies for a Content Hub workbook
    template.

.DESCRIPTION
    Copied from the body builders in Deploy-Workbooks
    (Deploy/content/Deploy-SentinelContentHub.ps1), unchanged in what they
    send.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentHub/ConvertTo-iSOCContentHubWorkbookRequest.ps1
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

function ConvertTo-iSOCContentHubWorkbookRequest {
    <#
    .SYNOPSIS
        Return the workbook body and the metadata body that links it to its
        solution.

    .DESCRIPTION
        The workbook is a shared workbook in the workspace's region, sourced
        from the workspace, in the sentinel category, tagged with the
        workspace's resource id (no host: with one, the workbook would not
        show in the Sentinel Workbooks blade). The metadata names the
        template's contentId and version, the workbook as parent, and the
        solution (its display name and contentId, found by the template's
        packageId; Unknown and the packageId when the catalogue has no
        match) as source.

    .PARAMETER Context
        The workspace context.

    .PARAMETER Template
        The workbook content template.

    .PARAMETER WorkbookResource
        The Microsoft.Insights/workbooks resource in its mainTemplate.

    .PARAMETER WorkbookName
        The workbook's resource name (a GUID).

    .PARAMETER DisplayName
        The template's display name, used when the resource has none.

    .PARAMETER AvailableSolutions
        The catalogue, from Get-iSOCContentHubCatalogue.

    .OUTPUTS
        [hashtable] Workbook and Metadata.

    .EXAMPLE
        $bodies = ConvertTo-iSOCContentHubWorkbookRequest -Context $ctx -Template $t -WorkbookResource $resource -WorkbookName $guid -DisplayName $name -AvailableSolutions $hub.Available
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Context,

        [Parameter(Mandatory)]
        [psobject] $Template,

        [Parameter(Mandatory)]
        [psobject] $WorkbookResource,

        [Parameter(Mandatory)]
        [string] $WorkbookName,

        [string] $DisplayName,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $AvailableSolutions
    )

    $wbProps = $WorkbookResource.properties
    $wbDisplayName = if ($wbProps -and ($wbProps.PSObject.Properties.Name -contains 'displayName')) { $wbProps.displayName } else { $DisplayName }
    $workspaceResourceId = $Context.WorkspaceResourceId

    $workbook = @{
        location   = $Context.Region
        kind       = 'shared'
        properties = @{
            displayName    = $wbDisplayName
            serializedData = $wbProps.serializedData
            version        = '1.0'
            sourceId       = $workspaceResourceId
            category       = 'sentinel'
        }
        tags       = @{
            'hidden-sentinelWorkspaceId' = $workspaceResourceId
            'hidden-sentinelContentType' = 'Workbook'
        }
    }

    $props = $Template.properties
    $contentId = if ($props.PSObject.Properties.Name -contains 'contentId') { $props.contentId } else { $null }
    $templateVersion = if ($props.PSObject.Properties.Name -contains 'version') { $props.version } else { $null }
    $packageId = if ($props.PSObject.Properties.Name -contains 'packageId') { $props.packageId } else { $null }
    $solution = if ($packageId) {
        $AvailableSolutions | Where-Object {
            (($_.properties.PSObject.Properties.Name -contains 'contentId') -and ($_.properties.contentId -eq $packageId)) -or ($_.name -eq $packageId)
        } | Select-Object -First 1
    }
    else { $null }
    $solutionName = if ($solution -and ($solution.properties.PSObject.Properties.Name -contains 'displayName')) { $solution.properties.displayName } else { 'Unknown' }
    $solutionContentId = if ($solution -and ($solution.properties.PSObject.Properties.Name -contains 'contentId')) { $solution.properties.contentId } else { $packageId }

    $metadata = @{
        properties = @{
            contentId = $contentId
            parentId  = "/subscriptions/$($Context.SubscriptionId)/resourceGroups/$($Context.ResourceGroup)/providers/Microsoft.Insights/workbooks/$WorkbookName"
            kind      = 'Workbook'
            version   = $templateVersion
            source    = @{
                kind     = 'Solution'
                name     = $solutionName
                sourceId = $solutionContentId
            }
        }
    }

    @{ Workbook = $workbook; Metadata = $metadata }
}

#Requires -Version 7.2

<#
.SYNOPSIS
    Which saved workbooks a Content Hub solution installed.

.DESCRIPTION
    Copied from the Content Hub exclusion in Tools/Export-SentinelWorkbooks.ps1.
    Content Hub marks what it installs with a Sentinel metadata record whose
    source is the solution; the workbook itself looks like any other.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentHub/Get-iSOCContentHubWorkbookLookup.ps1
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

function Get-iSOCContentHubWorkbookLookup {
    <#
    .SYNOPSIS
        Return the resource ids of the workbooks Content Hub solutions
        installed, each with its solution's name.

    .DESCRIPTION
        Reads the workspace's Sentinel metadata, every page, and keeps the
        parentId of each Workbook record whose source kind is Solution. A
        failed read is warned about and returns nothing, so an export goes
        on without telling Content Hub workbooks apart, as the script did.

    .PARAMETER Context
        The workspace context.

    .OUTPUTS
        [hashtable] The solution's name by workbook resource id, in any
        case.

    .EXAMPLE
        $hub = Get-iSOCContentHubWorkbookLookup -Context $ctx
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Context
    )

    $lookup = @{}
    Write-iSOCLog 'Querying Sentinel metadata to identify Content Hub workbooks...'
    try {
        $records = @(Invoke-iSOCRestRequest -Method GET -Path "$($Context.WorkspaceResourceId)/providers/Microsoft.SecurityInsights/metadata" -ApiVersion (Get-iSOCApiVersion SecurityInsights) -Context $Context)
    }
    catch {
        Write-iSOCLog "  Could not enumerate Sentinel metadata: $($_.Exception.Message)" -Level Warning
        Write-iSOCLog '  Continuing without Content Hub filtering.' -Level Warning
        return $lookup
    }

    foreach ($record in $records) {
        if ([string](Get-iSOCPropertyValue -InputObject $record -Path 'properties.kind') -ne 'Workbook') { continue }
        if ([string](Get-iSOCPropertyValue -InputObject $record -Path 'properties.source.kind') -ne 'Solution') { continue }
        $parentId = [string](Get-iSOCPropertyValue -InputObject $record -Path 'properties.parentId')
        if ($parentId) { $lookup[$parentId] = [string](Get-iSOCPropertyValue -InputObject $record -Path 'properties.source.name') }
    }
    Write-iSOCLog "  Identified $($lookup.Count) Content Hub workbook(s)."
    $lookup
}

#Requires -Version 7.6

<#
.SYNOPSIS
    What a compare found for one workspace item.

.NOTES
    File:         Modules/iSOCDeployments/Private/Drift/New-iSOCDriftItem.ps1
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

function New-iSOCDriftItem {
    <#
    .SYNOPSIS
        Build a drift item.

    .DESCRIPTION
        States:

          InSync                the workspace matches its source
          PortalEdit            a repository item changed in the workspace
          ContentHubCustomised  a Content Hub item changed in the workspace
          PortalOnly            in the workspace only: no repository item or
                                template (an orphan)
          Managed               Microsoft-managed; not compared
          Skipped               filtered out or excluded, with the reason

        Sync-iSOCContent sets SyncAction (Updated, Unchanged, Created,
        NoMatch or Failed) and SyncPath when it writes the item back.

    .PARAMETER ContentType
        The content type's name.

    .PARAMETER Item
        The item as the workspace returns it.

    .PARAMETER Source
        From the type's Classify handler.

    .PARAMETER State
        One of the states above.

    .PARAMETER Modification
        The differing fields, from Compare-iSOCContentBody.

    .OUTPUTS
        [pscustomobject] iSOCDeployments.DriftItem: ContentType, Name,
        ResourceName, Kind, Source, State, Reason, SourceRef, SourcePath,
        Solution, Enabled, Modifications, WorkspaceItem, SyncAction and
        SyncPath.

    .EXAMPLE
        New-iSOCDriftItem -ContentType AnalyticsRule -Item $rule -Source $source -State InSync
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds an object in memory; nothing outside the call changes.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $ContentType,

        [Parameter(Mandatory)]
        [psobject] $Item,

        [Parameter(Mandatory)]
        [hashtable] $Source,

        [Parameter(Mandatory)]
        [ValidateSet('InSync', 'PortalEdit', 'ContentHubCustomised', 'PortalOnly', 'Managed', 'Skipped')]
        [string] $State,

        [AllowEmptyCollection()]
        [object[]] $Modification = @()
    )

    $kind = Get-iSOCPropertyValue -InputObject $Item -Path 'kind'
    $enabled = Get-iSOCPropertyValue -InputObject $Item -Path 'properties.enabled'
    $displayName = Get-iSOCPropertyValue -InputObject $Item -Path 'properties.displayName'
    [pscustomobject]@{
        PSTypeName    = 'iSOCDeployments.DriftItem'
        ContentType   = $ContentType
        Name          = if ($null -ne $displayName) { [string]$displayName } else { $null }
        ResourceName  = [string](Get-iSOCPropertyValue -InputObject $Item -Path 'name')
        Kind          = if ($kind) { [string]$kind } else { 'Scheduled' }
        Source        = $Source.Source
        State         = $State
        Reason        = $Source.Reason
        SourceRef     = $Source.SourceRef
        SourcePath    = $Source.SourcePath
        Solution      = $Source.Solution
        Enabled       = if ($null -ne $enabled) { [bool]$enabled } else { $null }
        Modifications = @($Modification)
        WorkspaceItem = $Item
        SyncAction    = $null
        SyncPath      = $null
    }
}

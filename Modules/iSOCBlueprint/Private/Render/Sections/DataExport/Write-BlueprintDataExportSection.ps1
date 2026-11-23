#Requires -Version 7.6

<#
.SYNOPSIS
    Build the figures for and write 36-data-export.md.

.DESCRIPTION
    A step of the Blueprint renderer. Steps run in order and pass their results
    to later ones through the render context, so this one may also prepare
    figures that a later page uses.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/DataExport/Write-BlueprintDataExportSection.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.
function Write-BlueprintDataExportSection {
    <#
    .SYNOPSIS
        Build the figures for and write 36-data-export.md.

    .PARAMETER Context
        The render context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the render context.
    $m = $Context.m
    $n = $Context.n

    # Section 36 — Data export (TOC 4.3.3)
    $dataExports = Read-BlueprintRawArray 'data-exports.json'
    $linkedServices = Read-BlueprintRawArray 'linked-services.json'
    $linkedRows = @($linkedServices | ForEach-Object {
            $lp = if ($_.PSObject.Properties['properties'] -and $_.properties) { $_.properties } else { $null }
            [pscustomobject]@{
                Name                  = $_.name
                ResourceId            = if ($lp -and $lp.PSObject.Properties['resourceId']) { $lp.resourceId } else { '' }
                WriteAccessResourceId = if ($lp -and $lp.PSObject.Properties['writeAccessResourceId']) { $lp.writeAccessResourceId } else { '' }
            }
        })
    $exportRows = $dataExports | ForEach-Object {
        $dest = [string]$_.properties.destination.resourceId
        [pscustomobject]@{
            Name            = $_.name
            DestinationType = if ($dest -match '/storageAccounts/') { 'Storage account (Blob)' } elseif ($dest -match '/namespaces/') { 'Event Hub' } else { [string](Get-BlueprintRawProperty $_.properties.destination 'type' '') }
            Destination     = $dest
            Tables          = ($_.properties.tableNames -join ', ')
            Enabled         = $_.properties.enable
        }
    }
    $linkedStorageRows = @(Read-BlueprintRawArray 'linked-storage-accounts.json' | Where-Object { $_ } | ForEach-Object {
            $lp = Get-BlueprintRawProperty $_ 'properties'
            [pscustomobject]@{
                DataSource      = [string](Get-BlueprintRawProperty $lp 'dataSourceType' $_.name)
                StorageAccounts = (@(Get-BlueprintRawProperty $lp 'storageAccountIds' @()) | ForEach-Object { ([string]$_ -split '/')[-1] }) -join ', '
            }
        })
    $adxRows = @($linkedRows | Where-Object { $_.ResourceId -match '/providers/Microsoft\.Kusto/' } | ForEach-Object {
            [pscustomobject]@{ Name = $_.Name; Cluster = ($_.ResourceId -split '/')[-1]; ResourceId = $_.ResourceId }
        })
    Write-BlueprintSection '36-data-export.md' (@"
$(Format-Banner -Title "Data Export  (TOC 4.3.3)")

## Continuous data exports

Continuous export of selected tables to Storage Accounts or Event Hubs. Empty list = no data export configured.

$(Format-BlueprintTable -Items $exportRows -Columns 'Name','DestinationType','Destination','Tables','Enabled')

## Linked storage accounts

Customer-owned storage the workspace writes to, by data source type: custom and IIS logs, saved query results, alerts and ingestion. Empty when the workspace uses Microsoft-managed storage only.

$(Format-BlueprintTable -Items $linkedStorageRows -Columns 'DataSource','StorageAccounts' -EmptyMessage (Get-BlueprintEmptyMessage 'linked-storage-accounts.json'))

## ADX clusters linked to the workspace

Azure Data Explorer clusters linked through a workspace linked service, typically to keep data for longer outside the workspace.

$(Format-BlueprintTable -Items $adxRows -Columns 'Name','Cluster','ResourceId')

## Linked services

Workspace linked services: the automation account, the cluster, or the storage accounts used for customer-managed keys and private alert and query storage.

$(Format-BlueprintTable -Items $linkedRows -Columns 'Name','ResourceId','WriteAccessResourceId')

[Log Analytics data export (Microsoft Learn)](https://learn.microsoft.com/azure/azure-monitor/logs/logs-data-export) · [Linked storage accounts](https://learn.microsoft.com/azure/azure-monitor/logs/private-storage)
"@)
}

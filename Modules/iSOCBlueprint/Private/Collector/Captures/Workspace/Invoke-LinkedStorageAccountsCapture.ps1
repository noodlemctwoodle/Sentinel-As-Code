#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'linked-storage-accounts': writes linked-storage-accounts.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Workspace/Invoke-LinkedStorageAccountsCapture.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Collector
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Invoke-LinkedStorageAccountsCapture {
    <#
    .SYNOPSIS
        Capture 'linked-storage-accounts': writes linked-storage-accounts.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)

    $workspaceResourceId = $Context.workspaceResourceId

    # Customer-owned storage the workspace writes to (custom logs, query
    # results, alerts, ingestion), one entry per data source type.
    $lsa = Invoke-SentinelRest -Path "$workspaceResourceId/linkedStorageAccounts" -ApiVersion '2020-08-01'
    Save-Json -FileName 'linked-storage-accounts.json' -Data $lsa
}

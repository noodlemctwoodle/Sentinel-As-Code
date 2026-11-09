#Requires -Version 7.6

<#
.SYNOPSIS
    Read the content whose queries can depend on a classic table.

.DESCRIPTION
    Analytics rules and saved searches from the workspace; workbooks, data
    collection rules and Logic Apps from the whole subscription.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/ClassicToDcr/Read-iSOCTableMigrationContent.ps1
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

function Read-iSOCTableMigrationContent {
    <#
    .SYNOPSIS
        Read the content whose queries can depend on a classic table.

    .DESCRIPTION
        Analytics rules and saved searches come from the workspace;
        Sentinel workbooks, data collection rules and Logic Apps from the
        whole subscription, wherever they sit. Workbooks are listed with
        canFetchContent, without which the list carries no serializedData
        and no workbook has a query to scan, and one the list still returns
        without content is read on its own. A workbook, data collection
        rule or Logic App list that fails is a warning and an empty list;
        the analytics rules and saved searches must load.

    .PARAMETER Context
        The workspace context.

    .OUTPUTS
        [pscustomobject] AlertRules, SavedSearches, HuntingQueries (the
        saved searches in Hunting Queries), Parsers (those with a
        functionAlias), Workbooks, Dcrs and Playbooks.

    .EXAMPLE
        $content = Read-iSOCTableMigrationContent -Context $ctx
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Context
    )

    $subscription = "/subscriptions/$($Context.SubscriptionId)"
    $workspace = $Context.WorkspaceResourceId

    Write-iSOCLog '  Loading analytics rules...'
    $alertRules = @(Invoke-iSOCRestRequest -Method GET -Path "$workspace/providers/Microsoft.SecurityInsights/alertRules" -ApiVersion (Get-iSOCApiVersion SecurityInsightsPreview))

    Write-iSOCLog '  Loading saved searches (hunting queries and parsers)...'
    $savedSearches = @(Invoke-iSOCRestRequest -Method GET -Path "$workspace/savedSearches" -ApiVersion (Get-iSOCApiVersion SavedSearches))

    Write-iSOCLog '  Loading workbooks...'
    try {
        $workbooks = @(Invoke-iSOCRestRequest -Method GET -Path "$subscription/providers/Microsoft.Insights/workbooks?category=sentinel&canFetchContent=true" -ApiVersion (Get-iSOCApiVersion Workbooks))
    }
    catch {
        Write-iSOCLog "Workbook load failed: $($_.Exception.Message)" -Level Warning
        $workbooks = @()
    }
    $workbooks = @(foreach ($wb in $workbooks) {
            $id = [string](Get-iSOCPropertyValue -InputObject $wb -Path 'id')
            if ($id -and (Get-iSOCPropertyValue -InputObject $wb -Path 'properties') -and -not (Get-iSOCPropertyValue -InputObject $wb -Path 'properties.serializedData')) {
                try {
                    $detail = Invoke-iSOCRestRequest -Method GET -Path "$($id)?canFetchContent=true" -ApiVersion (Get-iSOCApiVersion Workbooks)
                    if (Get-iSOCPropertyValue -InputObject $detail -Path 'properties.serializedData') { $wb = $detail }
                }
                catch {
                    Write-iSOCLog "Workbook '$(Get-iSOCPropertyValue -InputObject $wb -Path 'properties.displayName')' content load failed: $($_.Exception.Message)" -Level Warning
                }
            }
            $wb
        })

    Write-iSOCLog '  Loading data collection rules...'
    try {
        $dcrs = @(Invoke-iSOCRestRequest -Method GET -Path "$subscription/providers/Microsoft.Insights/dataCollectionRules" -ApiVersion (Get-iSOCApiVersion DataCollectionRules))
    }
    catch {
        Write-iSOCLog "DCR load failed: $($_.Exception.Message)" -Level Warning
        $dcrs = @()
    }

    Write-iSOCLog '  Loading Logic Apps (playbooks)...'
    try {
        $logicApps = @(Invoke-iSOCRestRequest -Method GET -Path "$subscription/providers/Microsoft.Logic/workflows" -ApiVersion (Get-iSOCApiVersion LogicApps))
    }
    catch {
        Write-iSOCLog "Logic App load failed: $($_.Exception.Message)" -Level Warning
        $logicApps = @()
    }

    [pscustomobject]@{
        AlertRules     = $alertRules
        SavedSearches  = $savedSearches
        HuntingQueries = @($savedSearches | Where-Object { (Get-iSOCPropertyValue -InputObject $_ -Path 'properties.category') -eq 'Hunting Queries' })
        Parsers        = @($savedSearches | Where-Object { Get-iSOCPropertyValue -InputObject $_ -Path 'properties.functionAlias' })
        Workbooks      = $workbooks
        Dcrs           = $dcrs
        Playbooks      = $logicApps
    }
}

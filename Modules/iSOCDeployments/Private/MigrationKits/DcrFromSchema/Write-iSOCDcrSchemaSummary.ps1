#Requires -Version 7.6

<#
.SYNOPSIS
    Log what the run made and what to do next.

.DESCRIPTION
    Under -WhatIf no deploy commands are printed, as their files were never
    written.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/DcrFromSchema/Write-iSOCDcrSchemaSummary.ps1
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

function Write-iSOCDcrSchemaSummary {
    <#
    .SYNOPSIS
        Log what the run made and what to do next.

    .DESCRIPTION
        The table with its column count and the rule with its resource group
        and region. Then: under -WhatIf, that nothing was written; when
        nothing was deployed, the two New-AzResourceGroupDeployment commands
        in order, table first; when the rule was deployed with an endpoint,
        the Logs Ingestion URL to post to (granting the role first, when it
        was not granted) and the Test-iSOCDcrIngestion command that proves
        ingestion end to end.

    .PARAMETER Context
        The workspace context.

    .PARAMETER TableName
        The table name.

    .PARAMETER ColumnCount
        How many columns the table has.

    .PARAMETER Rule
        The rule settings, from Resolve-iSOCDcrSchemaRuleSetting.

    .PARAMETER DcrResourceGroupName
        The rule's resource group.

    .PARAMETER Location
        The rule's region.

    .PARAMETER Files
        The templates, from Write-iSOCDcrSchemaTemplate.

    .PARAMETER Deployment
        The deployment, from Invoke-iSOCDcrSchemaDeploy.

    .PARAMETER SkipTable
        No table was written.

    .EXAMPLE
        Write-iSOCDcrSchemaSummary -Context $ctx -TableName 'MyApp_CL' -ColumnCount 4 -Rule $rule -DcrResourceGroupName rg-sentinel -Location uksouth -Files $files -Deployment $deployment
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $Context,

        [Parameter(Mandatory)]
        [string] $TableName,

        [Parameter(Mandatory)]
        [int] $ColumnCount,

        [Parameter(Mandatory)]
        [psobject] $Rule,

        [Parameter(Mandatory)]
        [string] $DcrResourceGroupName,

        [Parameter(Mandatory)]
        [string] $Location,

        [Parameter(Mandatory)]
        [psobject] $Files,

        [Parameter(Mandatory)]
        [psobject] $Deployment,

        [switch] $SkipTable
    )

    Write-iSOCLog ''
    Write-iSOCLog 'Summary' -Level Section
    Write-iSOCLog "Table    : $TableName ($ColumnCount columns)"
    Write-iSOCLog "DCR      : $($Rule.DcrName) in $DcrResourceGroupName ($Location)"

    if ($WhatIfPreference) {
        Write-iSOCLog ''
        Write-iSOCLog 'Nothing was written or deployed (-WhatIf). Re-run without -WhatIf to produce the templates.'
    }
    elseif (-not $Deployment.Deployed) {
        Write-iSOCLog ''
        Write-iSOCLog 'Not deployed. Deploy in this order, table first:'
        if (-not $SkipTable) {
            Write-iSOCLog "  New-AzResourceGroupDeployment -ResourceGroupName $($Context.ResourceGroup) -TemplateFile '$($Files.TablePath)'"
        }
        Write-iSOCLog "  New-AzResourceGroupDeployment -ResourceGroupName $DcrResourceGroupName -TemplateFile '$($Files.DcrPath)'"
        Write-iSOCLog 'A DCR deployed before its table fails with InvalidOutputTable.'
    }
    elseif ($Deployment.Endpoint -and $Deployment.ImmutableId) {
        Write-iSOCLog ''
        if (@($Deployment.Granted).Count -gt 0) {
            Write-iSOCLog 'Next: the ingestion role is granted. POST your data to:'
        }
        else {
            Write-iSOCLog 'Next: grant Monitoring Metrics Publisher on the DCR (re-run with -GrantIngestionRoleTo), then POST to:'
        }
        Write-iSOCLog "  $($Deployment.Endpoint)/dataCollectionRules/$($Deployment.ImmutableId)/streams/$($Rule.StreamName)?api-version=2023-01-01"
        Write-iSOCLog ''
        Write-iSOCLog 'To prove ingestion end to end with synthetic data:'
        Write-iSOCLog "  Test-iSOCDcrIngestion -DcrName $($Rule.DcrName) -DcrResourceGroupName $DcrResourceGroupName -Follow"
    }
}

#Requires -Version 7.2

<#
.SYNOPSIS
    Deploy the table, then the data collection rule, read the rule's ingestion endpoint and grant the senders their role.

.DESCRIPTION
    The table goes first: a rule whose output stream names a missing table
    fails with InvalidOutputTable.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/DcrFromSchema/Invoke-iSOCDcrSchemaDeploy.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.0
    Last Updated: 2026-11-04
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Invoke-iSOCDcrSchemaDeploy {
    <#
    .SYNOPSIS
        Deploy the table, then the data collection rule, read the rule's
        ingestion endpoint and grant the senders their role.

    .DESCRIPTION
        Under -WhatIf no template was written, so a warning says there is
        nothing to deploy. Without -Deploy nothing is deployed. Otherwise,
        asking ShouldProcess for each: the table template (unless
        -SkipTable; a table template not written stops the run) to the
        workspace's resource group, then the rule's to its own, each
        validated first (Invoke-iSOCTemplateDeployment) and named
        <name>-<yyyyMMddHHmmss>. The rule's immutable id and logs
        ingestion endpoint are read back (a Direct rule with no endpoint is
        a warning: one cannot be added later), and each identity in
        GrantIngestionRoleTo is given Monitoring Metrics Publisher on it
        (Grant-iSOCDcrIngestionRole).

    .PARAMETER Context
        The workspace context.

    .PARAMETER TableName
        The table name.

    .PARAMETER Rule
        The rule settings, from Resolve-iSOCDcrSchemaRuleSetting.

    .PARAMETER DcrResourceGroupName
        The rule's resource group.

    .PARAMETER Files
        The templates, from Write-iSOCDcrSchemaTemplate.

    .PARAMETER GrantIngestionRoleTo
        The identities that will send to the rule.

    .PARAMETER Deploy
        Deploy the templates.

    .PARAMETER SkipTable
        Deploy no table.

    .OUTPUTS
        [pscustomobject] Deployed, ImmutableId, Endpoint and Granted.

    .EXAMPLE
        Invoke-iSOCDcrSchemaDeploy -Context $ctx -TableName 'MyApp_CL' -Rule $rule -DcrResourceGroupName rg-sentinel -Files $files -Deploy
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Context,

        [Parameter(Mandatory)]
        [string] $TableName,

        [Parameter(Mandatory)]
        [psobject] $Rule,

        [Parameter(Mandatory)]
        [string] $DcrResourceGroupName,

        [Parameter(Mandatory)]
        [psobject] $Files,

        [string[]] $GrantIngestionRoleTo,

        [switch] $Deploy,

        [switch] $SkipTable
    )

    $result = [pscustomobject]@{ Deployed = $false; ImmutableId = $null; Endpoint = $null; Granted = @() }

    if ($WhatIfPreference) {
        Write-iSOCLog 'Deploy' -Level Section
        Write-iSOCLog '-WhatIf writes no templates, so there is nothing to deploy. The lines above are what a real run would create.' -Level Warning
        return $result
    }
    if (-not $Deploy) { return $result }

    Write-iSOCLog 'Deploying' -Level Section
    $dcrName = $Rule.DcrName

    if (-not $SkipTable) {
        if (-not $Files.WroteTable) {
            throw 'The table template was not written, so it cannot be deployed. Re-run without -WhatIf.'
        }
        if ($PSCmdlet.ShouldProcess("$($Context.WorkspaceName)/$TableName", 'Deploy custom table')) {
            $slug = ($TableName -replace '_CL$', '').ToLowerInvariant()
            $null = Invoke-iSOCTemplateDeployment -Context $Context -ResourceGroupName $Context.ResourceGroup -Name "table-$slug" -TemplatePath $Files.TablePath
            Write-iSOCLog "Created $TableName." -Level Success
        }
    }

    if ($PSCmdlet.ShouldProcess("$DcrResourceGroupName/$dcrName", 'Deploy data collection rule')) {
        $null = Invoke-iSOCTemplateDeployment -Context $Context -ResourceGroupName $DcrResourceGroupName -Name $dcrName -TemplatePath $Files.DcrPath
        $result.Deployed = $true
        Write-iSOCLog "Deployed $dcrName." -Level Success

        $dcrId = "/subscriptions/$($Context.SubscriptionId)/resourceGroups/$DcrResourceGroupName/providers/Microsoft.Insights/dataCollectionRules/$dcrName"
        $ingestion = Get-iSOCDcrIngestionEndpoint -Context $Context -DcrId $dcrId
        if ($null -ne $ingestion.ImmutableId) {
            $result.ImmutableId = $ingestion.ImmutableId
            Write-iSOCLog "ImmutableId: $($result.ImmutableId)"
        }
        if ($ingestion.Endpoint) {
            $result.Endpoint = $ingestion.Endpoint
            Write-iSOCLog "Ingestion  : $($result.Endpoint)"
        }
        else {
            Write-iSOCLog 'No logsIngestion endpoint was returned for this Direct DCR. Endpoints cannot be added to an existing DCR, so this one needs a Data Collection Endpoint or a replacement DCR.' -Level Warning
        }

        if ($GrantIngestionRoleTo) {
            $result.Granted = @(Grant-iSOCDcrIngestionRole -Context $Context -DcrId $dcrId -DcrName $dcrName -Identity $GrantIngestionRoleTo)
        }
    }

    $result
}

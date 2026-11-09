#Requires -Version 7.6

<#
.SYNOPSIS
    Deploy a data collection rule's template, with the real cause when it fails.

.DESCRIPTION
    A resource group deployment named after the rule and the time; on failure
    the failed operations' messages are read and thrown.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/ClassicToDcr/Deploy-iSOCDcrTemplate.ps1
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

function Deploy-iSOCDcrTemplate {
    <#
    .SYNOPSIS
        Deploy a data collection rule's template, with the real cause when
        it fails.

    .DESCRIPTION
        Deploys the template file to the resource group as
        <rule>-<yyyyMMddHHmmss>. A failed deployment throws only a summary
        ("failed with 1 error"), so its failed operations are read and their
        status messages thrown instead; when they cannot be read the
        original error is. A deployment that ends in any state but
        Succeeded throws. The caller asks ShouldProcess.

    .PARAMETER Context
        The workspace context.

    .PARAMETER ResourceGroupName
        The resource group the rule goes in.

    .PARAMETER Name
        The rule's name.

    .PARAMETER TemplatePath
        The template file.

    .OUTPUTS
        [psobject] The deployment.

    .EXAMPLE
        Deploy-iSOCDcrTemplate -Context $ctx -ResourceGroupName rg-dcr -Name dcr-myapp -TemplatePath ./dcr-myapp.json
    #>
    [CmdletBinding()]
    [OutputType([psobject])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Context,

        [Parameter(Mandatory)]
        [string] $ResourceGroupName,

        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [string] $TemplatePath
    )

    $deploymentName = "$Name-$(Get-Date -Format 'yyyyMMddHHmmss')"
    try {
        $deployment = New-iSOCAzResourceGroupDeployment -Name $deploymentName -Parameters @{
            ResourceGroupName = $ResourceGroupName
            TemplateFile      = $TemplatePath
            Force             = $true
        }
    }
    catch {
        $detail = $null
        try {
            $operations = @(Invoke-iSOCRestRequest -Method GET -Path "/subscriptions/$($Context.SubscriptionId)/resourceGroups/$ResourceGroupName/providers/Microsoft.Resources/deployments/$deploymentName/operations" -ApiVersion (Get-iSOCApiVersion Deployments))
            $detail = @($operations |
                    Where-Object { (Get-iSOCPropertyValue -InputObject $_ -Path 'properties.provisioningState') -eq 'Failed' } |
                    ForEach-Object {
                        $message = Get-iSOCPropertyValue -InputObject $_ -Path 'properties.statusMessage'
                        if ($message -is [string]) { $message } else { ConvertTo-Json -InputObject $message -Depth 8 -Compress }
                    }) -join ' | '
        }
        catch {
            Write-iSOCLog "Could not read deployment operations: $($_.Exception.Message.Split([char]10)[0])" -Level Debug
        }
        if ($detail) { throw "Deployment failed: $detail" }
        throw
    }

    $state = [string](Get-iSOCPropertyValue -InputObject $deployment -Path 'ProvisioningState')
    if ($state -ne 'Succeeded') { throw "Deployment finished with state $state." }
    $deployment
}

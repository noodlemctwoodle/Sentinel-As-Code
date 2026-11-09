#Requires -Version 7.6

<#
.SYNOPSIS
    Validate a template against its resource group, then deploy it, with the real cause when either fails.

.DESCRIPTION
    A preflight rejection makes no deployment whose operations could be read,
    so the template is validated first.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/DcrFromSchema/Invoke-iSOCTemplateDeployment.ps1
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

function Invoke-iSOCTemplateDeployment {
    <#
    .SYNOPSIS
        Validate a template against its resource group, then deploy it, with
        the real cause when either fails.

    .DESCRIPTION
        Test-AzResourceGroupDeployment's errors carry the nested details a
        preflight rejection otherwise hides behind "See inner errors for
        details"; they are flattened (Format-iSOCDeploymentError) and
        thrown before anything deploys. Validation is best effort: when it
        cannot run, the deployment goes ahead. The deployment, and the
        reading of its failed operations, are Deploy-iSOCDcrTemplate's. The
        caller asks ShouldProcess.

    .PARAMETER Context
        The workspace context.

    .PARAMETER ResourceGroupName
        The resource group to deploy to.

    .PARAMETER Name
        The deployment's name, before its timestamp.

    .PARAMETER TemplatePath
        The template file.

    .OUTPUTS
        [psobject] The deployment.

    .EXAMPLE
        Invoke-iSOCTemplateDeployment -Context $ctx -ResourceGroupName rg-sentinel -Name table-myapp -TemplatePath ./table-myapp.json
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

    $validationErrors = $null
    try {
        $validationErrors = @(Test-iSOCAzResourceGroupDeployment -Parameters @{ ResourceGroupName = $ResourceGroupName; TemplateFile = $TemplatePath })
    }
    catch {
        Write-iSOCLog "Pre-deployment validation could not run: $($_.Exception.Message.Split([char]10)[0])" -Level Debug
    }

    if ($validationErrors -and $validationErrors.Count -gt 0) {
        $detail = @(@($validationErrors | ForEach-Object { Format-iSOCDeploymentError -ErrorObject $_ }) | Where-Object { $_ })
        if ($detail.Count -eq 0) {
            $detail = @(try { $validationErrors | ConvertTo-Json -Depth 12 -Compress }
                catch { ($validationErrors | Out-String).Trim() })
        }
        throw "Template validation failed ($TemplatePath): $($detail -join ' | ')"
    }

    Deploy-iSOCDcrTemplate -Context $Context -ResourceGroupName $ResourceGroupName -Name $Name -TemplatePath $TemplatePath
}

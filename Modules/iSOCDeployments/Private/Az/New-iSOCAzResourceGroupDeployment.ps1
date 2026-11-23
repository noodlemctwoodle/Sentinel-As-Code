#Requires -Version 7.6

<#
.SYNOPSIS
    Run a resource group deployment through Az.Resources.

.NOTES
    File:         Modules/iSOCDeployments/Private/Az/New-iSOCAzResourceGroupDeployment.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    Needs Az.Resources at run time; Assert-iSOCPrerequisite checks for it
    before a playbook deploy. This file defines functions rather than
    running.
#>

# Keeps the file help above from being read as the help of the function below.

function New-iSOCAzResourceGroupDeployment {
    <#
    .SYNOPSIS
        Deploy an ARM template to a resource group.

    .DESCRIPTION
        Splats the parameters onto New-AzResourceGroupDeployment, so the
        template's own parameters pass through by name, and stops on the
        first error. The caller asks ShouldProcess; a call that reaches here
        under -WhatIf throws instead of deploying, as a write reaching the
        REST client does.

    .PARAMETER Name
        The deployment name.

    .PARAMETER Parameters
        The New-AzResourceGroupDeployment parameters: ResourceGroupName,
        TemplateFile, optionally TemplateParameterFile, and template
        parameters.

    .OUTPUTS
        [psobject] The deployment, as New-AzResourceGroupDeployment returns
        it.

    .EXAMPLE
        New-iSOCAzResourceGroupDeployment -Name $name -Parameters $request.Body
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'The Deploy handler asks ShouldProcess before calling this; asking again would prompt twice under -Confirm.')]
    [CmdletBinding()]
    [OutputType([psobject])]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [hashtable] $Parameters
    )

    if ($WhatIfPreference) { throw "A deployment of '$($Parameters.TemplateFile)' reached New-iSOCAzResourceGroupDeployment under -WhatIf." }
    New-AzResourceGroupDeployment @Parameters -Name $Name -ErrorAction Stop -WhatIf:$false -Confirm:$false
}

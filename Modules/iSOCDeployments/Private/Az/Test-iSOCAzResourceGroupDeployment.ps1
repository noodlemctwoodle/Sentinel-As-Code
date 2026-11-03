#Requires -Version 7.2

<#
.SYNOPSIS
    Validate a resource group deployment through Az.Resources.

.NOTES
    File:         Modules/iSOCDeployments/Private/Az/Test-iSOCAzResourceGroupDeployment.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.0
    Last Updated: 2026-11-03
    Requires:     PowerShell 7.2+

    Needs Az.Resources at run time; Assert-iSOCPrerequisite checks for it
    before a playbook deploy. This file defines functions rather than
    running.
#>

# Keeps the file help above from being read as the help of the function below.

function Test-iSOCAzResourceGroupDeployment {
    <#
    .SYNOPSIS
        Ask ARM whether a template would deploy to a resource group.

    .DESCRIPTION
        Splats the parameters onto Test-AzResourceGroupDeployment, which
        validates without deploying and so runs under -WhatIf. It takes no
        deployment name, so none is passed.

    .PARAMETER Parameters
        The deployment parameters, as for New-iSOCAzResourceGroupDeployment.

    .OUTPUTS
        [psobject] The validation errors, if any; nothing when the template
        is valid.

    .EXAMPLE
        $problems = @(Test-iSOCAzResourceGroupDeployment -Parameters $request.Body)
    #>
    [CmdletBinding()]
    [OutputType([psobject])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Parameters
    )

    Test-AzResourceGroupDeployment @Parameters -ErrorAction Stop
}

#Requires -Version 7.6

<#
.SYNOPSIS
    Deploy handler for playbooks: run one template as a resource group
    deployment.

.DESCRIPTION
    Copied from the deployment step of Deploy-CustomPlaybooks
    (Deploy/content/Deploy-CustomContent.ps1). Under -WhatIf the template is
    validated against the playbook resource group instead; the script passed
    the deployment name to the validation too, which
    Test-AzResourceGroupDeployment has no parameter for, so its validation
    always failed (MIGRATION.md edit E14).

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/Playbook/Invoke-iSOCPlaybookDeploy.ps1
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

function Invoke-iSOCPlaybookDeploy {
    <#
    .SYNOPSIS
        Deploy one playbook template, or validate it under -WhatIf.

    .DESCRIPTION
        The deployment is named Playbook-<file name>-<local time as
        yyyyMMddHHmmss>, with the file name cut so the whole name fits
        ARM's 64 characters, as the script named it. Validation
        problems under -WhatIf are logged as warnings and do not fail the
        playbook, as before.

    .PARAMETER Run
        The deploy run.

    .PARAMETER ContentType
        The playbook content type.

    .PARAMETER Item
        A repository item from Read-iSOCPlaybookRepo that passed
        Test-iSOCPlaybook.

    .OUTPUTS
        [hashtable] Outcome (Deployed or WhatIf) and Reason.

    .EXAMPLE
        $sent = Invoke-iSOCPlaybookDeploy -Run $run -ContentType $playbooks -Item $item
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'ContentType', Justification = 'Every Deploy handler takes the same parameters; a playbook deploys through Az.Resources, not the type''s REST path.')]
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Run,

        [Parameter(Mandatory)]
        [psobject] $ContentType,

        [Parameter(Mandatory)]
        [psobject] $Item
    )

    $request = ConvertTo-iSOCPlaybookRequest -Item $Item -Context $Run.Context
    $parameters = $request.Body
    if ($parameters.ContainsKey('TemplateParameterFile')) { Write-iSOCLog "  Using parameters file: $($Item.BaseName).parameters.json" -Level Debug }
    foreach ($name in $request.Injected) { Write-iSOCLog "  Injected parameter: $name" -Level Debug }

    if (-not $PSCmdlet.ShouldProcess($Item.RelativePath, "Deploy playbook '$($Item.Name)'")) {
        try {
            $problems = @(Test-iSOCAzResourceGroupDeployment -Parameters $parameters | Where-Object { $null -ne $_ })
            if ($problems.Count -eq 0) {
                Write-iSOCLog "[WhatIf] Template validation passed for '$($Item.Name)'." -Level Success
            } else {
                $detail = @($problems | ForEach-Object { if ($_.PSObject.Properties['Message']) { $_.Message } else { [string]$_ } }) -join '; '
                Write-iSOCLog "[WhatIf] Template validation failed for '$($Item.Name)': $detail" -Level Warning
            }
        } catch {
            Write-iSOCLog "[WhatIf] Template validation failed for '$($Item.Name)': $($_.Exception.Message)" -Level Warning
        }
        return @{ Outcome = 'WhatIf'; Reason = '' }
    }

    $timestamp = Get-Date -Format 'yyyyMMddHHmmss'
    $maxNameLen = 64 - 10 - $timestamp.Length
    $truncatedName = if ($Item.BaseName.Length -gt $maxNameLen) { $Item.BaseName.Substring(0, $maxNameLen) } else { $Item.BaseName }
    New-iSOCAzResourceGroupDeployment -Name "Playbook-$truncatedName-$timestamp" -Parameters $parameters | Out-Null
    @{ Outcome = 'Deployed'; Reason = '' }
}

#Requires -Version 7.6

<#
.SYNOPSIS
    Send one workspace setting, with the workspace's etag for it.

.DESCRIPTION
    Copied from the Configure Sentinel Settings step of
    Pipelines/Sentinel-Deploy.yml and .github/workflows/sentinel-deploy.yml,
    which read each setting for its etag and then wrote it.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/WorkspaceSetting/Invoke-iSOCWorkspaceSettingDeploy.ps1
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

function Invoke-iSOCWorkspaceSettingDeploy {
    <#
    .SYNOPSIS
        Send one workspace setting, with the workspace's etag for it.

    .DESCRIPTION
        The setting is read first: when the workspace has it, its etag goes
        in the request, so the write replaces that version; when it does not
        (a 404), the setting is created. Then the request
        ConvertTo-iSOCWorkspaceSettingRequest builds is sent with PUT.

        A refusal for want of permission (401 or 403) skips the setting with
        a warning rather than failing it, as the pipelines warned and went
        on: UEBA and Entity Analytics need the Security Administrator
        directory role, which Initialize-iSOCServicePrincipal -SkipEntraRole
        leaves out, so a deployment without it still deploys everything
        else. The next run tries the setting again. Any other failure throws,
        and deploy fails the item.

        Under -WhatIf nothing is read or sent.

    .PARAMETER Run
        The deployment run.

    .PARAMETER ContentType
        The workspace setting content type.

    .PARAMETER Item
        A repository item that passed Test-iSOCWorkspaceSetting.

    .OUTPUTS
        [hashtable] Outcome (Deployed, Skipped or WhatIf) and Reason.

    .EXAMPLE
        $sent = Invoke-iSOCWorkspaceSettingDeploy -Run $run -ContentType $type -Item $item
    #>
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

    $request = Invoke-iSOCContentTypeHandler -ContentType $ContentType -Handler ToRequest -Parameters @{ Item = $Item }
    if (-not $PSCmdlet.ShouldProcess($Item.RelativePath, "Deploy workspace setting '$($request.ResourceName)'")) {
        return @{ Outcome = 'WhatIf'; Reason = '' }
    }

    $path = Get-iSOCResourcePath -Context $Run.Context -ContentType $ContentType -Name $request.ResourceName
    $apiVersion = Get-iSOCApiVersion $ContentType.ApiVersion
    try {
        $current = Invoke-iSOCRestRequest -Method GET -Path $path -ApiVersion $apiVersion -AllowNotFound
        $etag = [string](Get-iSOCPropertyValue -InputObject $current -Path 'etag')
        $body = [ordered]@{ kind = $request.Body.kind }
        if ($etag) { $body.etag = $etag }
        $body.properties = $request.Body.properties
        Invoke-iSOCRestRequest -Method PUT -Path $path -ApiVersion $apiVersion -Body $body | Out-Null
    } catch {
        $status = $_.Exception.PSObject.Properties['StatusCode']
        if (-not $status -or [int]$status.Value -notin 401, 403) { throw }
        $reason = if ($request.Body.kind -in 'Ueba', 'EntityAnalytics') {
            'not authorised to change it: UEBA and Entity Analytics need the Security Administrator directory role, which Initialize-iSOCServicePrincipal grants unless -SkipEntraRole'
        } else {
            'not authorised to change it: the deployment needs Microsoft Sentinel Contributor on the workspace'
        }
        Write-iSOCLog "Skipping '$($Item.RelativePath)': $reason." -Level Warning
        return @{ Outcome = 'Skipped'; Reason = $reason }
    }
    @{ Outcome = 'Deployed'; Reason = '' }
}

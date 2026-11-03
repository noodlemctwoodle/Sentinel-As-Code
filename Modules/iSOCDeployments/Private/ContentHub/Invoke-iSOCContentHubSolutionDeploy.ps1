#Requires -Version 7.2

<#
.SYNOPSIS
    Install or update one Content Hub solution.

.DESCRIPTION
    Copied from Deploy-Solution (Deploy/content/Deploy-SentinelContentHub.ps1).

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentHub/Invoke-iSOCContentHubSolutionDeploy.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.0
    Last Updated: 2026-11-03
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Invoke-iSOCContentHubSolutionDeploy {
    <#
    .SYNOPSIS
        Deploy a solution's package to the workspace's resource group and
        say how it went.

    .DESCRIPTION
        A solution that needs nothing is left alone. Otherwise its full
        catalogue entry is read and its packaged content deployed as an
        incremental ARM deployment named sentinel-<catalogue name> (at most
        64 characters), with the postDeployment metadata that makes
        deployments fail taken out first. A package over the 4 MB ARM
        request limit is not sent: ARM would refuse it with HTTP 413. A
        solution with no packaged content is registered as a content package
        only. After a deployment the command pauses 1.5 seconds.

    .PARAMETER Context
        The workspace context.

    .PARAMETER SolutionStatus
        From Get-iSOCContentHubSolutionStatus.

    .OUTPUTS
        [hashtable] Outcome (Deployed for an install, Updated, Unchanged,
        WhatIf or Failed) and Reason.

    .EXAMPLE
        Invoke-iSOCContentHubSolutionDeploy -Context $ctx -SolutionStatus $status
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Context,

        [Parameter(Mandatory)]
        [hashtable] $SolutionStatus
    )

    $solutionName = $SolutionStatus.Name
    $catalogEntry = $SolutionStatus.CatalogEntry
    $action = $SolutionStatus.Action
    $done = if ($action -eq 'Install') { 'Deployed' } else { 'Updated' }

    if ($action -eq 'None') {
        Write-iSOCLog "  $solutionName v$($SolutionStatus.InstalledVersion) - no update required."
        return @{ Outcome = 'Unchanged'; Reason = 'current' }
    }

    if (-not $PSCmdlet.ShouldProcess($solutionName, "$action Content Hub solution")) {
        Write-iSOCLog "  [WhatIf] Would $($action.ToLower()) solution: $solutionName (v$($SolutionStatus.InstalledVersion) -> v$($SolutionStatus.AvailableVersion))"
        return @{ Outcome = 'WhatIf'; Reason = $action.ToLower() }
    }

    Write-iSOCLog "  Deploying solution: $solutionName ($action, v$($SolutionStatus.AvailableVersion))..."
    $root = "$($Context.WorkspaceResourceId)/providers/Microsoft.SecurityInsights"
    $apiVersion = Get-iSOCApiVersion SecurityInsights

    try {
        $detailedSolution = Invoke-iSOCRestRequest -Method GET -Path "$root/contentProductPackages/$($catalogEntry.name)" -ApiVersion $apiVersion
    }
    catch {
        Write-iSOCLog "  Failed to retrieve package details for $solutionName : $($_.Exception.Message)" -Level Error
        return @{ Outcome = 'Failed'; Reason = "could not read the package: $($_.Exception.Message)" }
    }

    $packagedContent = if ($detailedSolution.properties.PSObject.Properties.Name -contains 'packagedContent') { $detailedSolution.properties.packagedContent } else { $null }

    if (-not $packagedContent) {
        Write-iSOCLog "  No packaged content found for $solutionName. Registering package only." -Level Warning
        try {
            $catProps = $catalogEntry.properties
            $catContentId = if ($catProps.PSObject.Properties.Name -contains 'contentId') { $catProps.contentId } else { $catalogEntry.name }
            $catProductId = if ($catProps.PSObject.Properties.Name -contains 'contentProductId') { $catProps.contentProductId } else { $null }
            $catVersion = if ($catProps.PSObject.Properties.Name -contains 'version') { $catProps.version } else { '1.0.0' }
            $packageBody = @{
                properties = @{
                    contentId        = $catContentId
                    contentProductId = $catProductId
                    contentKind      = 'Solution'
                    version          = $catVersion
                    displayName      = $solutionName
                }
            }
            Invoke-iSOCRestRequest -Method PUT -Path "$root/contentPackages/$catContentId" -ApiVersion $apiVersion -Body $packageBody | Out-Null
            Write-iSOCLog "  Registered package for $solutionName." -Level Success
            return @{ Outcome = $done; Reason = 'registered the package only' }
        }
        catch {
            Write-iSOCLog "  Failed to register package for $solutionName : $($_.Exception.Message)" -Level Error
            return @{ Outcome = 'Failed'; Reason = "could not register the package: $($_.Exception.Message)" }
        }
    }

    foreach ($resource in $packagedContent.resources) {
        if ($resource.properties -and
            $resource.properties.PSObject.Properties.Name -contains 'mainTemplate' -and
            $resource.properties.mainTemplate -and
            $resource.properties.mainTemplate.PSObject.Properties.Name -contains 'metadata' -and
            $resource.properties.mainTemplate.metadata -and
            $resource.properties.mainTemplate.metadata.PSObject.Properties.Name -contains 'postDeployment') {
            $resource.properties.mainTemplate.metadata.postDeployment = $null
        }
    }

    $fullName = "sentinel-$($catalogEntry.name)"
    $deploymentName = $fullName.Substring(0, [Math]::Min(64, $fullName.Length))
    $deploymentPath = "/subscriptions/$($Context.SubscriptionId)/resourcegroups/$($Context.ResourceGroup)/providers/Microsoft.Resources/deployments/$deploymentName"

    try {
        $jsonBody = ConvertTo-iSOCSolutionDeploymentJson -PackagedContent $packagedContent -Workspace $Context.WorkspaceName -Region $Context.Region
    }
    catch {
        Write-iSOCLog "  Failed to serialise deployment body for $solutionName : $($_.Exception.Message)" -Level Error
        return @{ Outcome = 'Failed'; Reason = "could not serialise the package: $($_.Exception.Message)" }
    }

    $maxBytes = 4MB
    $bodyBytes = [System.Text.Encoding]::UTF8.GetByteCount($jsonBody)
    if ($bodyBytes -gt $maxBytes) {
        $bodyMB = [Math]::Round($bodyBytes / 1MB, 2)
        $limitMB = [Math]::Round($maxBytes / 1MB, 2)
        Write-iSOCLog "  $solutionName v$($SolutionStatus.AvailableVersion) is $bodyMB MB as a deployment request, over the $limitMB MB ARM limit. Skipping it rather than sending a request ARM will reject with HTTP 413." -Level Error
        return @{ Outcome = 'Failed'; Reason = "the package is $bodyMB MB, over the $limitMB MB ARM limit" }
    }

    try {
        Invoke-iSOCRestRequest -Method PUT -Path $deploymentPath -ApiVersion (Get-iSOCApiVersion Deployments) -Body $jsonBody | Out-Null
        Write-iSOCLog "  Successfully deployed solution: $solutionName v$($SolutionStatus.AvailableVersion)" -Level Success
        Start-Sleep -Milliseconds 1500
        @{ Outcome = $done; Reason = '' }
    }
    catch {
        Write-iSOCLog "  Deployment failed for $solutionName : $($_.Exception.Message)" -Level Error
        @{ Outcome = 'Failed'; Reason = $_.Exception.Message }
    }
}

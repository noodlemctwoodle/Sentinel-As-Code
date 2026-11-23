#Requires -Version 7.6

<#
.SYNOPSIS
    Save the workbooks the requested Content Hub solutions ship.

.DESCRIPTION
    Copied from Deploy-Workbooks (Deploy/content/Deploy-SentinelContentHub.ps1).
    Installing a solution registers its workbook templates but saves no
    workbook, so this step saves each one to the workspace's resource
    group and links it to its solution.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentHub/Invoke-iSOCContentHubWorkbookDeploy.ps1
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

function Invoke-iSOCContentHubWorkbookDeploy {
    <#
    .SYNOPSIS
        Save or update a workbook from each of the solutions' workbook
        templates, and return one result per template.

    .DESCRIPTION
        Reads the Workbook and WorkbookTemplate templates and the
        workspace's workbook metadata. A workbook counts as saved only when
        its metadata's parent is a Microsoft.Insights workbook: a solution
        install writes metadata pointing at the template itself. For each
        template of a requested solution:
        - one marked [Deprecated] is skipped;
        - a saved workbook at the template's version is unchanged, unless
          its solution was installed or updated in this run or
          -ForceContentDeployment is given; otherwise it is updated in
          place, keeping its name, and an unsaved one is created under a
          new GUID;
        - the template's detail is read by contentId, then by name, falling
          back to the listing's own mainTemplate; a template with no
          workbook resource fails, and one with no mainTemplate or no
          serializedData is skipped;
        - the workbook is saved, then its metadata written; a metadata
          failure is a warning, and the workbook stays saved.
        When the templates cannot be read the step logs an error and
        returns nothing, as the script did.

    .PARAMETER Context
        The workspace context.

    .PARAMETER SolutionNames
        The solutions whose workbooks to save.

    .PARAMETER AvailableSolutions
        The catalogue, from Get-iSOCContentHubCatalogue.

    .PARAMETER NewSolutions
        The solutions installed or updated in this run.

    .PARAMETER ForceContentDeployment
        Save workbooks that are current again.

    .OUTPUTS
        [pscustomobject] iSOCDeployments.ContentHubResult, one per template.

    .EXAMPLE
        $results = @(Invoke-iSOCContentHubWorkbookDeploy -Context $ctx -SolutionNames $names -AvailableSolutions $hub.Available)
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Context,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $SolutionNames,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $AvailableSolutions,

        [AllowEmptyCollection()]
        [string[]] $NewSolutions = @(),

        [switch] $ForceContentDeployment
    )

    Write-iSOCLog 'Deploying Workbooks...' -Level Section
    try {
        $allTemplates = @(Get-iSOCContentHubTemplate -Context $Context -Kind Workbook, WorkbookTemplate -ExpandMainTemplate)
        Write-iSOCLog "Found $($allTemplates.Count) Workbook templates."
    } catch {
        Write-iSOCLog "Failed to fetch Workbook templates: $($_.Exception.Message)" -Level Error
        return
    }

    $lookup = Get-iSOCContentHubSolutionLookup -SolutionNames $SolutionNames -AvailableSolutions $AvailableSolutions
    $targetTemplates = @($allTemplates | Where-Object { ($_.properties.PSObject.Properties.Name -contains 'packageId') -and $lookup.ById.ContainsKey($_.properties.packageId) })
    Write-iSOCLog "Found $($targetTemplates.Count) Workbook templates for target solutions."
    if ($targetTemplates.Count -eq 0) { return }

    $root = "$($Context.WorkspaceResourceId)/providers/Microsoft.SecurityInsights"
    $apiVersion = Get-iSOCApiVersion SecurityInsights
    $existingWorkbooks = @()
    try {
        $existingWorkbooks = @(Invoke-iSOCRestRequest -Method GET -Path "$root/metadata?`$filter=$([uri]::EscapeDataString("(properties/kind eq 'Workbook')"))" -ApiVersion $apiVersion)
        Write-iSOCLog "Found $($existingWorkbooks.Count) existing workbook metadata entries."
    } catch {
        Write-iSOCLog "Could not fetch workbook metadata: $($_.Exception.Message)" -Level Warning
    }

    $existingByContentId = @{}
    foreach ($wb in $existingWorkbooks) {
        if ($wb.properties.PSObject.Properties.Name -notcontains 'contentId') { continue }
        $parentId = if ($wb.properties.PSObject.Properties.Name -contains 'parentId') { $wb.properties.parentId } else { $null }
        if (-not ($parentId -match '/providers/Microsoft\.Insights/workbooks/')) { continue }
        $existingByContentId[$wb.properties.contentId] = $wb
    }

    foreach ($template in $targetTemplates) {
        $props = $template.properties
        $displayName = if ($props.PSObject.Properties.Name -contains 'displayName') { $props.displayName } else { 'Unknown' }
        $contentId = if ($props.PSObject.Properties.Name -contains 'contentId') { $props.contentId } else { $null }
        $templateVersion = if ($props.PSObject.Properties.Name -contains 'version') { $props.version } else { $null }
        $solution = $lookup.ById[$props.packageId]
        $emit = {
            param([string] $Outcome, [string] $Reason)
            New-iSOCContentHubResult -ContentType Workbook -Name $displayName -Identity $contentId -Solution $solution -Outcome $Outcome -Reason $Reason
        }

        if ($displayName -match '\[Deprecated\]') {
            & $emit Deprecated 'the template is deprecated'
            continue
        }

        $fromNew = [bool]($solution -and $NewSolutions -contains $solution)
        $existingMeta = if ($contentId) { $existingByContentId[$contentId] } else { $null }
        $needsUpdate = $false
        if ($existingMeta -and -not $ForceContentDeployment -and -not $fromNew) {
            $existingVersion = if ($existingMeta.properties.PSObject.Properties.Name -contains 'version') { $existingMeta.properties.version } else { $null }
            if ($existingVersion -and $templateVersion -and $existingVersion -eq $templateVersion) {
                & $emit Unchanged 'current'
                continue
            }
            $needsUpdate = $true
        } elseif ($existingMeta) {
            $needsUpdate = $true
        }

        $verb = if ($needsUpdate) { 'update' } else { 'deploy' }
        if (-not $PSCmdlet.ShouldProcess($displayName, "$(if ($needsUpdate) { 'Update' } else { 'Save' }) Content Hub workbook")) {
            Write-iSOCLog "  [WhatIf] Would $verb workbook: $displayName"
            & $emit WhatIf $verb
            continue
        }

        $detailedTemplate = $null
        foreach ($tmplId in @($contentId, $template.name) | Where-Object { $_ }) {
            try {
                $detailedTemplate = Invoke-iSOCRestRequest -Method GET -Path "$root/contentTemplates/$tmplId" -ApiVersion $apiVersion
                break
            } catch {
                continue
            }
        }
        if (-not $detailedTemplate) {
            if ($props.PSObject.Properties.Name -contains 'mainTemplate' -and $props.mainTemplate) {
                $detailedTemplate = $template
            } else {
                Write-iSOCLog "  Failed to fetch template details for workbook: $displayName; skipping" -Level Warning
                & $emit Failed 'could not read the template'
                continue
            }
        }

        if (-not (($detailedTemplate.properties.PSObject.Properties.Name -contains 'mainTemplate') -and ($null -ne $detailedTemplate.properties.mainTemplate))) {
            Write-iSOCLog "  No mainTemplate for workbook: $displayName; skipping" -Level Warning
            & $emit Skipped 'the template has no mainTemplate'
            continue
        }

        $workbookResource = $detailedTemplate.properties.mainTemplate.resources | Where-Object {
            ($_.PSObject.Properties.Name -contains 'type') -and ($_.type -eq 'Microsoft.Insights/workbooks')
        } | Select-Object -First 1
        if (-not $workbookResource) {
            Write-iSOCLog "  No workbook resource found in template: $displayName" -Level Warning
            & $emit Failed 'the template has no workbook resource'
            continue
        }

        $guid = if ($needsUpdate -and $existingMeta -and ($existingMeta.properties.PSObject.Properties.Name -contains 'parentId')) {
            if ($existingMeta.properties.parentId -match '/([^/]+)$') { $Matches[1] } else { (New-Guid).Guid }
        } else {
            (New-Guid).Guid
        }

        $wbProps = $workbookResource.properties
        $hasData = $wbProps -and ($wbProps.PSObject.Properties.Name -contains 'serializedData') -and $wbProps.serializedData
        if (-not $hasData) {
            Write-iSOCLog "  No serializedData found in workbook template: $displayName; skipping" -Level Warning
            & $emit Skipped 'the workbook has no serializedData'
            continue
        }

        $bodies = ConvertTo-iSOCContentHubWorkbookRequest -Context $Context -Template $template -WorkbookResource $workbookResource -WorkbookName $guid -DisplayName $displayName -AvailableSolutions $AvailableSolutions
        $workbookPath = "/subscriptions/$($Context.SubscriptionId)/resourceGroups/$($Context.ResourceGroup)/providers/Microsoft.Insights/workbooks/$guid"
        try {
            Invoke-iSOCRestRequest -Method PUT -Path $workbookPath -ApiVersion (Get-iSOCApiVersion Workbooks) -Body $bodies.Workbook | Out-Null
            if ($needsUpdate) {
                Write-iSOCLog "  Updated workbook: $displayName" -Level Success
                & $emit Updated ''
            } else {
                Write-iSOCLog "  Deployed workbook: $displayName" -Level Success
                & $emit Deployed ''
            }
            try {
                Invoke-iSOCRestRequest -Method PUT -Path "$root/metadata/workbook-$guid" -ApiVersion $apiVersion -Body $bodies.Metadata | Out-Null
            } catch {
                Write-iSOCLog "  Workbook deployed but metadata failed: $displayName ($($_.Exception.Message))" -Level Warning
            }
        } catch {
            Write-iSOCLog "  Failed to deploy workbook: $displayName - $($_.Exception.Message)" -Level Error
            & $emit Failed $_.Exception.Message
        }

        Start-Sleep -Milliseconds 500
    }
}

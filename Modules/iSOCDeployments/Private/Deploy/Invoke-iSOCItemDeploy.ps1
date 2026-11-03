#Requires -Version 7.2

<#
.SYNOPSIS
    Deploy one content item: decide, validate, check dependencies, send.

.DESCRIPTION
    The per-item steps of Deploy-CustomParsers, Deploy-CustomWatchlists,
    Deploy-CustomDetections and Deploy-CustomHuntingQueries
    (Deploy/content/Deploy-CustomContent.ps1), in one place for every
    content type, with the type's own handlers doing what differs.

.NOTES
    File:         Modules/iSOCDeployments/Private/Deploy/Invoke-iSOCItemDeploy.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.2.0
    Last Updated: 2026-11-03
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Invoke-iSOCItemDeploy {
    <#
    .SYNOPSIS
        Run one item through deploy and return what happened.

    .DESCRIPTION
        In order, as the scripts did:

        1. Smart deployment and the exclusions decide whether the item is
           considered at all (Unchanged or Skipped).
        2. The type's Validate handler can stop it: a file that does not
           parse fails, anything else is skipped.
        3. When the type checks dependencies, a missing one skips the item
           or sends it disabled, as the type's MissingDependency says.
        4. The type's Deploy handler sends it, or the request from its
           ToRequest handler is sent as it is.

        A successful send records the item's files as deployed in the state;
        a failure forgets them, so the next run retries. Under -WhatIf
        nothing is sent and the state is not touched.

    .PARAMETER Run
        The deployment run.

    .PARAMETER ContentType
        The item's content type.

    .PARAMETER Item
        A repository item.

    .OUTPUTS
        [pscustomobject] iSOCDeployments.ItemResult.

    .EXAMPLE
        $result = Invoke-iSOCItemDeploy -Run $run -ContentType $type -Item $item
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Run,

        [Parameter(Mandatory)]
        [psobject] $ContentType,

        [Parameter(Mandatory)]
        [psobject] $Item
    )

    $name = $ContentType.Name
    $label = $Item.RelativePath
    $files = @(Get-iSOCItemFile -Item $Item -RepoPath $Run.RepoPath)
    $setState = {
        param([string] $Status)
        foreach ($file in $files) { Set-iSOCDeploymentItemState -State $Run.State -Key $file -Status $Status }
    }

    $decision = Test-iSOCShouldDeployItem -Run $Run -Item $Item
    switch ($decision.Reason) {
        'Excluded' {
            Write-iSOCLog "Excluded by $($Run.Config.Path): $label"
            return (New-iSOCItemResult -ContentType $name -Item $Item -Outcome Skipped -Reason "excluded by $($Run.Config.Path)")
        }
        'Unchanged' {
            Write-iSOCLog "Unchanged: $label; skipping (smart deployment)"
            return (New-iSOCItemResult -ContentType $name -Item $Item -Outcome Unchanged -Reason 'smart deployment: unchanged')
        }
        'Retry' { Write-iSOCLog "Retrying: $label; not previously deployed successfully" -Level Warning }
    }

    # Validate reports a parse error too, after anything it checks first (a
    # watchlist's missing files). An item fails when its first problem is
    # the parse error and is skipped for anything else, as the scripts did.
    $issues = @(Invoke-iSOCContentTypeHandler -ContentType $ContentType -Handler Validate -Parameters @{ Item = $Item })
    if ($issues.Count -gt 0) {
        if ($Item.ParseError -and ([string]$issues[0]).EndsWith([string]$Item.ParseError)) {
            Write-iSOCLog "Failed to deploy '$label': $($issues[0])" -Level Error
            & $setState 'failed'
            return (New-iSOCItemResult -ContentType $name -Item $Item -Outcome Failed -Reason $issues[0])
        }
        Write-iSOCLog "Skipping '$label': $($issues[0])" -Level Warning
        return (New-iSOCItemResult -ContentType $name -Item $Item -Outcome Skipped -Reason $issues[0])
    }

    $disabled = $false
    $missing = @()
    if ($ContentType.MissingDependency -ne 'Deploy') {
        $check = Test-iSOCItemDependency -Run $Run -Item $Item
        if (-not $check.Passed) {
            $missing = @($check.Missing)
            if ($ContentType.MissingDependency -eq 'Skip') {
                Write-iSOCLog "Skipping '$label': missing dependencies: $($missing -join ', ')" -Level Warning
                return (New-iSOCItemResult -ContentType $name -Item $Item -Outcome Skipped -Reason 'missing dependencies' -Missing $missing)
            }
            Write-iSOCLog "Missing dependencies for '$label': $($missing -join ', '); deploying as disabled" -Level Warning
            $disabled = $true
        }
    }

    Write-iSOCLog "Processing: $($Item.Name) [$label]"
    try {
        if ($ContentType.Handlers.ContainsKey('Deploy')) {
            $parameters = @{ Run = $Run; ContentType = $ContentType; Item = $Item }
            if ($disabled) { $parameters.Disabled = $true }
            $sent = Invoke-iSOCContentTypeHandler -ContentType $ContentType -Handler Deploy -Parameters $parameters
        }
        else {
            $parameters = @{ Item = $Item }
            if ((Get-Command -Name $ContentType.Handlers.ToRequest).Parameters.ContainsKey('Context')) { $parameters.Context = $Run.Context }
            $request = Invoke-iSOCContentTypeHandler -ContentType $ContentType -Handler ToRequest -Parameters $parameters
            $sent = if ($PSCmdlet.ShouldProcess($label, "Deploy $($ContentType.DisplayName.ToLowerInvariant()) '$($Item.Name)'")) {
                Send-iSOCContentRequest -Context $Run.Context -ContentType $ContentType -Request $request | Out-Null
                @{ Outcome = 'Deployed'; Reason = '' }
            }
            else {
                @{ Outcome = 'WhatIf'; Reason = '' }
            }
        }
    }
    catch {
        Write-iSOCLog "Failed to deploy '$label': $($_.Exception.Message)" -Level Error
        & $setState 'failed'
        return (New-iSOCItemResult -ContentType $name -Item $Item -Outcome Failed -Reason $_.Exception.Message -Missing $missing)
    }

    switch ($sent.Outcome) {
        'WhatIf' { Write-iSOCLog "[WhatIf] Would deploy: $($Item.Name)" }
        'Skipped' { }
        default {
            $note = if ($sent.Reason) { " (disabled: $($sent.Reason))" } else { '' }
            Write-iSOCLog "Deployed$($note): $($Item.Name)" -Level Success
            & $setState 'success'
        }
    }
    New-iSOCItemResult -ContentType $name -Item $Item -Outcome $sent.Outcome -Reason $sent.Reason -Missing $missing
}

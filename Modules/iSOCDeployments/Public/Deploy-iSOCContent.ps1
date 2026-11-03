#Requires -Version 7.2

<#
.SYNOPSIS
    Deploy-iSOCContent: deploy repository content to the connected
    workspace.

.DESCRIPTION
    Replaces Deploy/content/Deploy-CustomContent.ps1 for the content types
    the module has ported: parsers, watchlists, analytics rules and hunting
    queries so far. The script's -Skip<Type> switches become
    -ExcludeContentType, -SkipCommunityDetections becomes
    -Exclude 'Content/AnalyticalRules/Community/*', and -ResourceGroup,
    -Workspace, -Region and -IsGov come from Connect-iSOCWorkspace
    (MIGRATION.md edit E12).

.NOTES
    File:         Modules/iSOCDeployments/Public/Deploy-iSOCContent.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.0
    Last Updated: 2026-11-03
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter and
    per-example detail lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Deploy-iSOCContent {
    <#
    .SYNOPSIS
        Deploy the repository's content to the connected workspace, type by
        type in dependency order.

    .DESCRIPTION
        Content types deploy in their deploy order: parsers, watchlists,
        analytics rules, then hunting queries. For each item:

        - sentinel-deployment.config can exclude it, and with
          -SmartDeployment it deploys only when git reports it changed or
          its last deployment did not succeed;
        - an item that does not validate is skipped, and one whose file
          does not parse fails;
        - with dependencies.json, the workspace's tables, watchlists and
          functions are read first, and an item whose dependency is missing
          is skipped, or for an analytics rule deployed disabled;
        - Community rules always deploy disabled, and a rule whose query
          the service will not validate yet is deployed disabled.

        After watchlists are uploaded the command waits 30 seconds for
        Sentinel to index them, before the rules that read them.
        deployment-state.json records what succeeded, for smart deployment
        next time. With -WhatIf it reads everything, reports what it would
        deploy, and changes nothing: not the workspace, not the state file.

        A failed item does not stop the run. In a pipeline, pass the result
        on: exit (Deploy-iSOCContent).ExitCode

    .PARAMETER ContentType
        The content types to deploy, by name or wildcard. Defaults to every
        type the module can deploy (Get-iSOCContentType shows them).

    .PARAMETER ExcludeContentType
        Content types to leave out, by name or wildcard.

    .PARAMETER Exclude
        Repository-relative paths, or wildcards, of items to leave out, such
        as 'Content/AnalyticalRules/Community/*' for the Community rules.

    .PARAMETER SmartDeployment
        Deploy only what git reports changed in the commit being deployed,
        and anything whose last deployment did not succeed. When the change
        cannot be worked out, everything deploys.

    .PARAMETER Context
        The workspace to deploy to. Defaults to the one Connect-iSOCWorkspace
        connected.

    .PARAMETER RepoPath
        The repository root. Defaults to the repository the current folder
        is in.

    .OUTPUTS
        [pscustomobject] iSOCDeployments.DeployRun: Deployed, Skipped,
        Failed, WhatIf (the counts), Duration, ExitCode and Results (one
        iSOCDeployments.ItemResult per item: ContentType, Name, Identity,
        RelativePath, Outcome, Reason, Missing).

    .EXAMPLE
        Connect-iSOCWorkspace -ResourceGroup rg-sentinel -WorkspaceName law-sentinel
        Deploy-iSOCContent -WhatIf

        Shows what every content type would deploy, changing nothing.

    .EXAMPLE
        $run = Deploy-iSOCContent -SmartDeployment -Exclude 'Content/AnalyticalRules/Community/*'
        exit $run.ExitCode

        A pipeline step: deploys what changed, holds the Community rules
        back, and fails the step when anything failed.

    .EXAMPLE
        (Deploy-iSOCContent -ContentType Watchlist, AnalyticsRule).Results | Where-Object Outcome -ne Deployed

        Deploys watchlists and rules only, and lists everything that did
        not deploy as written, with the reason.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('iSOCDeployments.DeployRun')]
    param(
        [SupportsWildcards()]
        [string[]] $ContentType,

        [SupportsWildcards()]
        [string[]] $ExcludeContentType,

        [SupportsWildcards()]
        [string[]] $Exclude,

        [switch] $SmartDeployment,

        [psobject] $Context,

        [string] $RepoPath
    )

    Assert-iSOCPrerequisite -Step Connect, Read
    $ctx = Resolve-iSOCContext -Context $Context
    $repo = Resolve-iSOCRepoPath -RepoPath $RepoPath

    $types = @(Get-iSOCContentTypeDefinition -Name $ContentType)
    if ($ContentType) {
        $cannot = @($types | Where-Object { $_.Capabilities -notcontains 'Deploy' })
        if ($cannot.Count -gt 0) { throw "The module cannot deploy $(($cannot | ForEach-Object { $_.Name }) -join ', ') yet." }
    }
    else {
        $types = @($types | Where-Object { $_.Capabilities -contains 'Deploy' })
    }
    if ($ExcludeContentType) {
        $types = @($types | Where-Object { $typeName = $_.Name; -not @($ExcludeContentType | Where-Object { $typeName -like $_ }).Count })
    }

    Write-iSOCLog ('=' * 60)
    Write-iSOCLog "  Content deployment to workspace $($ctx.WorkspaceName)" -Level Section
    Write-iSOCLog ('=' * 60)
    if ($WhatIfPreference) { Write-iSOCLog 'DRY RUN MODE: no changes will be made.' -Level Warning }
    Write-iSOCLog "  Content types: $(($types | ForEach-Object { $_.Name }) -join ', ')"
    if ($Exclude) { Write-iSOCLog "  Excluding:     $($Exclude -join ', ')" }

    $config = Get-iSOCDeploymentConfig -RepoPath $repo
    $changed = $null
    if ($SmartDeployment) {
        Write-iSOCLog 'Smart deployment enabled; detecting changed files...' -Level Section
        $changed = @(Get-iSOCChangedFile -RepoPath $repo)
        if ($changed.Count -gt 0) {
            Write-iSOCLog "  Detected $($changed.Count) changed file(s):"
            foreach ($cf in $changed) { Write-iSOCLog "    - $cf" }
        }
        else { $changed = $null }
    }
    else {
        Write-iSOCLog 'Smart deployment disabled; all content will be deployed.'
    }

    $state = Read-iSOCDeploymentState -RepoPath $repo
    $graph = Read-iSOCDependencyGraph -RepoPath $repo
    $run = New-iSOCDeployRun -Context $ctx -RepoPath $repo -Config $config -ChangedFiles $changed -State $state -Graph $graph
    if ($graph.Count -gt 0) { $run.Inventory = Get-iSOCWorkspaceInventory -Run $run }

    foreach ($type in $types) {
        Write-iSOCLog ''
        Write-iSOCLog "Deploying $($type.DisplayName.ToLowerInvariant())..." -Level Section
        $items = @(Invoke-iSOCContentTypeHandler -ContentType $type -Handler ReadRepo -Parameters @{ RepoPath = $repo; ContentType = $type })
        if ($Exclude) {
            $kept = @($items | Where-Object { $path = $_.RelativePath; -not @($Exclude | Where-Object { $path -like $_ }).Count })
            if ($kept.Count -lt $items.Count) { Write-iSOCLog "Left out $($items.Count - $kept.Count) item(s) matching -Exclude." }
            $items = $kept
        }
        if ($items.Count -eq 0) { Write-iSOCLog "No $($type.DisplayName.ToLowerInvariant()) to deploy."; continue }
        Write-iSOCLog "Found $($items.Count) item(s) to process."

        $before = $run.Results.Count
        foreach ($item in Get-iSOCDeployOrder -Run $run -Item $items) {
            $run.Results.Add((Invoke-iSOCItemDeploy -Run $run -ContentType $type -Item $item))
        }

        $sentAny = @($run.Results | Select-Object -Skip $before | Where-Object { $_.Outcome -in 'Deployed', 'DeployedDisabled' }).Count -gt 0
        if ($sentAny -and $type.SettleSeconds -gt 0) {
            Write-iSOCLog "Waiting $($type.SettleSeconds)s for $($type.DisplayName.ToLowerInvariant()) to propagate..."
            Start-Sleep -Seconds $type.SettleSeconds
        }
        if (-not $WhatIfPreference) { Save-iSOCDeploymentState -State $run.State }
    }

    Write-iSOCDeploySummary -Run $run -ContentType $types
}

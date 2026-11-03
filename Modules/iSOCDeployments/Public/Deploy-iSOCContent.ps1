#Requires -Version 7.2

<#
.SYNOPSIS
    Deploy-iSOCContent: deploy repository content to the connected
    workspace.

.DESCRIPTION
    Replaces Deploy/content/Deploy-CustomContent.ps1 (parsers, watchlists,
    analytics rules, hunting queries, playbooks, workbooks, automation
    rules and summary rules) and Deploy/content/Deploy-DefenderDetections.ps1
    (Defender XDR custom detections). The script's -Skip<Type> switches
    become -ExcludeContentType, -SkipCommunityDetections becomes
    -Exclude 'Content/AnalyticalRules/Community/*', and -ResourceGroup,
    -Workspace, -Region and -IsGov come from Connect-iSOCWorkspace
    (MIGRATION.md edits E12 and E17).

.NOTES
    File:         Modules/iSOCDeployments/Public/Deploy-iSOCContent.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.3.0
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
        analytics rules, hunting queries, playbooks, workbooks, automation
        rules, summary rules, then Defender XDR custom detections. For each
        item:

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

        Playbooks deploy as ARM templates to the playbook resource group
        through Az.Resources, which is needed only when there are playbooks
        to deploy; the templates in Module folders go first, each after the
        modules it calls. Under -WhatIf each template is validated against
        the resource group instead. After watchlists are uploaded the
        command waits 30 seconds for Sentinel to index them, before the
        rules that read them.

        Defender XDR custom detections go to Microsoft Graph for the tenant
        the workspace is in, which needs the CustomDetection.ReadWrite.All
        application permission. The tenant's rules are read first; a
        detection whose display name the tenant has is updated in place,
        and a new one is created with the id its file gives it. Under
        -WhatIf the rules are still read, so the dry run says which it
        would update, which create, and which would fail for want of an
        id.

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
        Deploy-iSOCContent -ContentType DefenderDetection -WhatIf

        Reads the tenant's custom detection rules and shows which repository
        detections would be updated and which created, changing nothing.

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
    Assert-iSOCPrerequisite -Step Connect, Read

    # Every type is read before anything deploys, so a type's own
    # prerequisite (Az.Resources for playbooks) stops the run at the start,
    # and only when there is something of that type to deploy.
    $found = [ordered]@{}
    foreach ($type in $types) {
        $items = @(Invoke-iSOCContentTypeHandler -ContentType $type -Handler ReadRepo -Parameters @{ RepoPath = $repo; ContentType = $type })
        # Wrapped whole: an if statement's output is unrolled.
        $kept = @(if ($Exclude) { $items | Where-Object { $path = $_.RelativePath; -not @($Exclude | Where-Object { $path -like $_ }).Count } } else { $items })
        $found[$type.Name] = @{ Read = $items.Count; Items = $kept }
        if ($kept.Count -gt 0 -and @($type.Prerequisites).Count -gt 0) {
            Assert-iSOCPrerequisite -Name $type.Prerequisites -Purpose "deploying $(Get-iSOCContentTypeNoun -ContentType $type)"
        }
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
        Write-iSOCLog "Deploying $(Get-iSOCContentTypeNoun -ContentType $type)..." -Level Section
        $items = @($found[$type.Name].Items)
        $leftOut = $found[$type.Name].Read - $items.Count
        if ($leftOut -gt 0) { Write-iSOCLog "Left out $leftOut item(s) matching -Exclude." }
        if ($items.Count -eq 0) { Write-iSOCLog "No $(Get-iSOCContentTypeNoun -ContentType $type) to deploy."; continue }
        Write-iSOCLog "Found $($items.Count) item(s) to process."

        $before = $run.Results.Count
        $ordered = if ($type.Handlers.ContainsKey('Order')) {
            Invoke-iSOCContentTypeHandler -ContentType $type -Handler Order -Parameters @{ Item = $items }
        }
        else {
            Get-iSOCDeployOrder -Run $run -Item $items
        }
        foreach ($item in $ordered) {
            $run.Results.Add((Invoke-iSOCItemDeploy -Run $run -ContentType $type -Item $item))
        }

        $sentAny = @($run.Results | Select-Object -Skip $before | Where-Object { $_.Outcome -in 'Deployed', 'DeployedDisabled' }).Count -gt 0
        if ($sentAny -and $type.SettleSeconds -gt 0) {
            Write-iSOCLog "Waiting $($type.SettleSeconds)s for $(Get-iSOCContentTypeNoun -ContentType $type) to propagate..."
            Start-Sleep -Seconds $type.SettleSeconds
        }
        if (-not $WhatIfPreference) { Save-iSOCDeploymentState -State $run.State }
    }

    Write-iSOCDeploySummary -Run $run -ContentType $types
}

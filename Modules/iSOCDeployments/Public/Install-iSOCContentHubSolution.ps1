#Requires -Version 7.6

<#
.SYNOPSIS
    Install-iSOCContentHubSolution: install Content Hub solutions and
    deploy the content they ship.

.DESCRIPTION
    Replaces Deploy/content/Deploy-SentinelContentHub.ps1. The script's
    -Skip<Kind> switches become -ExcludeContentType, -SkipSolutionDeployment
    becomes -ExcludeContentType Solution, -ProtectCustomisedRules $false
    becomes -OverwriteCustomisedRules, and -SubscriptionId, -ResourceGroup,
    -Workspace, -Region and -IsGov come from Connect-iSOCWorkspace
    (MIGRATION.md edit E19).

.NOTES
    File:         Modules/iSOCDeployments/Public/Install-iSOCContentHubSolution.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter and
    per-example detail lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Install-iSOCContentHubSolution {
    <#
    .SYNOPSIS
        Install or update Content Hub solutions in the connected workspace,
        then deploy the analytics rules and workbooks they ship.

    .DESCRIPTION
        For the solutions named:

        1. Waits up to three minutes for the workspace's onboarding to
           read, then reads the Content Hub catalogue and what the workspace
           has installed, and logs a table of where each solution stands.
        2. Installs solutions that are new, updates those the catalogue has
           a newer version of (and, with -ForceSolutionUpdate, those that
           are current), as ARM deployments of their packages. A solution
           the catalogue does not have fails.
        3. Creates a rule from each analytics rule template the solutions
           ship, of the severities asked for, linked to its template and
           its solution. A rule made from a template is updated when the
           template is newer, when its solution was installed or updated in
           this run, or when -DisableRules finds it enabled. A rule changed
           in the workspace (its query, schedule, trigger or severity), or
           one with a template's name but no link to it, is left alone with
           a warning unless -OverwriteCustomisedRules is given.
        4. Saves each workbook the solutions ship, or updates it when the
           template is newer.
        5. Counts the automation rules and hunting queries the solutions
           ship: they arrive with the solution package and are not deployed
           separately.

        When a solution was installed or updated, the command waits a
        minute for its templates to appear before it reads them. With
        -WhatIf it reads everything, reports what it would do, and writes
        nothing.

        A failed item does not stop the run. In a pipeline, pass the result
        on: exit (Install-iSOCContentHubSolution -Name ...).ExitCode

        On a Microsoft ISOC workspace (the Defender portal's SIEM
        packaging), Content Hub is documented to install only a solution's
        data connectors during the preview; each item's outcome says what
        happened rather than the run assuming a full install.

    .PARAMETER Name
        The solutions' display names, as the Content Hub catalogue spells
        them (matched in any case). One comma-separated string is split, as
        a pipeline variable gives it.

    .PARAMETER Severity
        The analytics rule severities to deploy. Defaults to all four.

    .PARAMETER DisableRules
        Deploy analytics rules disabled, and disable rules made from the
        solutions' templates that are enabled.

    .PARAMETER ExcludeContentType
        What to leave out: Solution (install nothing; deploy content from
        solutions already installed), AnalyticsRule, Workbook,
        AutomationRule or HuntingQuery.

    .PARAMETER ForceSolutionUpdate
        Reinstall solutions that are already current.

    .PARAMETER ForceContentDeployment
        Redeploy rules and workbooks that are already current.

    .PARAMETER OverwriteCustomisedRules
        Update analytics rules that were changed in the workspace, instead of
        leaving them alone.

    .PARAMETER Context
        The workspace to deploy to. Defaults to the one Connect-iSOCWorkspace
        connected.

    .OUTPUTS
        [pscustomobject] iSOCDeployments.ContentHubRun: Solutions, Results
        (one iSOCDeployments.ContentHubResult per solution, rule template and
        workbook template: ContentType, Name, Identity, Solution, Outcome,
        Reason), the counts Deployed, Updated, Unchanged, Protected, Skipped,
        Failed and WhatIf, MetadataLinked, MetadataFailed,
        AutomationRuleTemplates, HuntingQueryTemplates, Duration and
        ExitCode.

    .EXAMPLE
        Connect-iSOCWorkspace -ResourceGroup rg-sentinel -WorkspaceName law-sentinel
        Install-iSOCContentHubSolution -Name 'Azure Activity', 'Microsoft Entra ID' -WhatIf

        Shows what installing two solutions would do, changing nothing.

    .EXAMPLE
        $run = Install-iSOCContentHubSolution -Name $env:SOLUTIONS -Severity High, Medium -DisableRules
        exit $run.ExitCode

        A pipeline step: a comma-separated list of solutions, their High and
        Medium rules deployed disabled.

    .EXAMPLE
        (Install-iSOCContentHubSolution -Name 'Azure Activity' -ExcludeContentType Solution).Results | Where-Object Outcome -eq Protected

        Redeploys the content of an installed solution and lists the rules
        left alone because they were changed in the workspace.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('iSOCDeployments.ContentHubRun')]
    param(
        [Parameter(Mandatory)]
        [string[]] $Name,

        [ValidateSet('High', 'Medium', 'Low', 'Informational')]
        [string[]] $Severity = @('High', 'Medium', 'Low', 'Informational'),

        [switch] $DisableRules,

        [ValidateSet('Solution', 'AnalyticsRule', 'Workbook', 'AutomationRule', 'HuntingQuery')]
        [string[]] $ExcludeContentType = @(),

        [switch] $ForceSolutionUpdate,

        [switch] $ForceContentDeployment,

        [switch] $OverwriteCustomisedRules,

        [psobject] $Context
    )

    $started = Get-Date
    $ctx = Resolve-iSOCContext -Context $Context
    Assert-iSOCPrerequisite -Step Connect

    $solutions = @($Name)
    if ($solutions.Count -eq 1 -and $solutions[0] -match ',') {
        $solutions = @($solutions[0] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }
    $protect = -not $OverwriteCustomisedRules
    $excluded = { param([string] $Kind) $ExcludeContentType -contains $Kind }

    Write-iSOCLog ('=' * 64) -Level Section
    Write-iSOCLog "  Content Hub deployment to workspace $($ctx.WorkspaceName)" -Level Section
    Write-iSOCLog ('=' * 64) -Level Section
    if ($WhatIfPreference) { Write-iSOCLog 'DRY RUN MODE: no changes will be made.' -Level Warning }
    Write-iSOCLog 'Configuration:'
    Write-iSOCLog "  Solutions:          $($solutions -join ', ')"
    Write-iSOCLog "  Severities:         $($Severity -join ', ')"
    Write-iSOCLog "  Disable Rules:      $([bool]$DisableRules)"
    Write-iSOCLog "  Protect Customised: $protect"
    Write-iSOCLog "  Excluding:          $(if ($ExcludeContentType.Count -gt 0) { $ExcludeContentType -join ', ' } else { 'nothing' })"

    $hub = Get-iSOCContentHubCatalogue -Context $ctx
    $statuses = @(foreach ($solution in $solutions) {
            Get-iSOCContentHubSolutionStatus -SolutionName $solution -AvailableSolutions $hub.Available -InstalledLookup $hub.InstalledLookup -Context $ctx -ForceSolutionUpdate:$ForceSolutionUpdate
        })
    Write-iSOCContentHubSolutionReport -SolutionStatuses $statuses

    $results = [System.Collections.Generic.List[object]]::new()
    if (-not (& $excluded 'Solution')) {
        Write-iSOCLog 'Phase 1: Solution Deployment' -Level Section
        foreach ($status in $statuses) {
            $catalogueName = if ($status.CatalogEntry) { [string]$status.CatalogEntry.name } else { $null }
            if ($status.Status -eq 'NotFound') {
                $results.Add((New-iSOCContentHubResult -ContentType Solution -Name $status.Name -Identity $catalogueName -Solution $status.Name -Outcome Failed -Reason 'not in the Content Hub catalogue'))
                continue
            }
            $sent = Invoke-iSOCContentHubSolutionDeploy -Context $ctx -SolutionStatus $status
            $results.Add((New-iSOCContentHubResult -ContentType Solution -Name $status.Name -Identity $catalogueName -Solution $status.Name -Outcome $sent.Outcome -Reason $sent.Reason))
        }
    }
    else {
        Write-iSOCLog 'Skipping solution deployment (Solution excluded).'
    }

    $newSolutions = @($statuses | Where-Object { $_.Action -in 'Install', 'Update', 'ForceUpdate' } | ForEach-Object { $_.Name })
    if ($newSolutions.Count -gt 0) { Write-iSOCLog "Freshly deployed solutions (content will be force-processed): $($newSolutions -join ', ')" }
    $installedNow = @($results | Where-Object { $_.ContentType -eq 'Solution' -and $_.Outcome -in 'Deployed', 'Updated' }).Count -gt 0

    $metadata = @{ Linked = 0; Failed = 0 }
    $automationRules = 0
    $huntingQueries = 0
    $contentSolutions = @($statuses | Where-Object { $_.Status -ne 'NotFound' } | ForEach-Object { $_.Name })
    if ($contentSolutions.Count -eq 0) {
        Write-iSOCLog 'No valid solutions found. Skipping content deployment.' -Level Warning
    }
    else {
        if (-not (& $excluded 'AnalyticsRule')) {
            foreach ($result in Invoke-iSOCContentHubRuleDeploy -Context $ctx -SolutionNames $contentSolutions -AvailableSolutions $hub.Available -Severity $Severity `
                    -NewSolutions $newSolutions -DisableRules:$DisableRules -ForceContentDeployment:$ForceContentDeployment -ProtectCustomisedRules $protect `
                    -PropagationSeconds $(if ($installedNow) { 60 } else { 0 }) -Metadata $metadata) {
                $results.Add($result)
            }
        }
        else { Write-iSOCLog 'Skipping Analytics Rule deployment (AnalyticsRule excluded).' }

        if (-not (& $excluded 'Workbook')) {
            foreach ($result in Invoke-iSOCContentHubWorkbookDeploy -Context $ctx -SolutionNames $contentSolutions -AvailableSolutions $hub.Available -NewSolutions $newSolutions -ForceContentDeployment:$ForceContentDeployment) {
                $results.Add($result)
            }
        }
        else { Write-iSOCLog 'Skipping Workbook check (Workbook excluded).' }

        if (-not (& $excluded 'AutomationRule')) {
            $automationRules = Get-iSOCContentHubTemplateCount -Context $ctx -Kind AutomationRule -SolutionNames $contentSolutions -AvailableSolutions $hub.Available
        }
        else { Write-iSOCLog 'Skipping Automation Rule check (AutomationRule excluded).' }

        if (-not (& $excluded 'HuntingQuery')) {
            $huntingQueries = Get-iSOCContentHubTemplateCount -Context $ctx -Kind HuntingQuery -SolutionNames $contentSolutions -AvailableSolutions $hub.Available
        }
        else { Write-iSOCLog 'Skipping Hunting Query check (HuntingQuery excluded).' }
    }

    Write-iSOCContentHubSummary -Results @($results) -Metadata $metadata -AutomationRuleTemplates $automationRules -HuntingQueryTemplates $huntingQueries -Started $started
}

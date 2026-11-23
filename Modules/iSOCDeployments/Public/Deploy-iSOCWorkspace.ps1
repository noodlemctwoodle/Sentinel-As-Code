#Requires -Version 7.6

<#
.SYNOPSIS
    Deploy-iSOCWorkspace: run the deploy pipelines' stages after the
    infrastructure, in order, as one command.

.DESCRIPTION
    Replaces the stage sequence of Pipelines/Sentinel-Deploy.yml and
    .github/workflows/sentinel-deploy.yml after Bicep: workspace settings,
    Content Hub solutions, custom content and Defender XDR custom
    detections, with the stage conditions and the dependency manifest guard
    that held them together (MIGRATION.md edit E44).

.NOTES
    File:         Modules/iSOCDeployments/Public/Deploy-iSOCWorkspace.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-05
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter and
    per-example detail lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Deploy-iSOCWorkspace {
    <#
    .SYNOPSIS
        Deploy workspace settings, Content Hub solutions, custom content and
        Defender XDR custom detections to the connected workspace, in order.

    .DESCRIPTION
        The stages, in the order the deploy pipelines run them after the
        infrastructure stage:

          WorkspaceSettings   Deploy-iSOCContent -ContentType WorkspaceSetting
          ContentHub          Install-iSOCContentHubSolution
          CustomContent       Test-iSOCDependencyManifest, then
                              Deploy-iSOCContent for every other type
          DefenderDetections  Deploy-iSOCContent -ContentType DefenderDetection

        A stage does not run when the stage that gates it failed, as the
        pipelines' stage conditions had it: a failed Content Hub stage holds
        back custom content, and failed custom content holds back the
        Defender detections. A stage that was left out, or did not run,
        holds back nothing, so the Defender detections still deploy after a
        failed Content Hub stage. Workspace settings gate nothing.

        Custom content deploys only when dependencies.json matches the
        content, as the pipelines' guard step required; otherwise the stage
        fails with the fix.

        Each stage's command logs its own run. Under -WhatIf every stage
        reads what it needs and changes nothing. Registering resource
        providers and deploying Infra/sentinel/main.bicep stay with the
        pipeline, before this command; Get-iSOCWorkspaceOnboarding says
        whether Bicep must run. In a pipeline, pass the result on:
        exit (Deploy-iSOCWorkspace ...).ExitCode

    .PARAMETER Stage
        The stages to run. Defaults to all four.

    .PARAMETER ExcludeStage
        Stages to leave out, such as ContentHub for a run that should not
        install or update solutions.

    .PARAMETER Solution
        The Content Hub solutions to install or update, by display name.
        Needed when the ContentHub stage runs.

    .PARAMETER Severity
        The analytics rule severities the Content Hub stage deploys from
        templates. Defaults to all four.

    .PARAMETER DisableRules
        Create the Content Hub stage's analytics rules disabled.

    .PARAMETER OverwriteCustomisedRules
        Let the Content Hub stage update rules that were changed in the
        workspace; without it they are left alone.

    .PARAMETER ForceSolutionUpdate
        Deploy Content Hub solutions that are already current.

    .PARAMETER ForceContentDeployment
        Deploy Content Hub rules and workbooks that are already current.

    .PARAMETER ExcludeSolutionContentType
        What the Content Hub stage leaves out: Solution, AnalyticsRule,
        Workbook, AutomationRule or HuntingQuery.

    .PARAMETER ExcludeContentType
        Content types the CustomContent stage leaves out, by name or
        wildcard (Get-iSOCContentType names them). Workspace settings and
        Defender detections have stages of their own: leave them out with
        -ExcludeStage.

    .PARAMETER Exclude
        Repository-relative paths, or wildcards, of items every stage leaves
        out, such as 'Content/AnalyticalRules/Community/*' for the Community
        rules.

    .PARAMETER SmartDeployment
        Deploy only what git reports changed, and anything whose last
        deployment did not succeed, in every stage that deploys repository
        content.

    .PARAMETER Context
        The workspace to deploy to. Defaults to the one Connect-iSOCWorkspace
        connected.

    .PARAMETER RepoPath
        The repository root. Defaults to the repository the current folder
        is in.

    .OUTPUTS
        [pscustomobject] iSOCDeployments.WorkspaceDeployRun: Stages (one
        iSOCDeployments.StageResult each: Stage, Outcome (Succeeded, Failed,
        Excluded or NotRun), Reason, ExitCode and Run, the stage command's
        result), Failed (the count of failed stages), Duration and ExitCode
        (1 when a stage failed).

    .EXAMPLE
        Connect-iSOCWorkspace -ResourceGroup rg-sentinel -WorkspaceName law-sentinel
        Deploy-iSOCWorkspace -Solution 'Microsoft Entra ID', 'Azure Activity' -DisableRules -WhatIf

        Shows what every stage would deploy, changing nothing.

    .EXAMPLE
        $run = Deploy-iSOCWorkspace -Solution $solutions -DisableRules -SmartDeployment -Exclude 'Content/AnalyticalRules/Community/*'
        exit $run.ExitCode

        A pipeline's deploy step, with the pipelines' defaults: solution
        rules created disabled, customised rules protected, only changed
        content deployed and the Community rules held back.

    .EXAMPLE
        Deploy-iSOCWorkspace -ExcludeStage ContentHub, DefenderDetections -ExcludeContentType Playbook

        Deploys the workspace settings and the custom content but the
        playbooks.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'Each stage command asks ShouldProcess for each write; -WhatIf and -Confirm reach them through Invoke-iSOCWorkspaceStage.')]
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('iSOCDeployments.WorkspaceDeployRun')]
    param(
        [ValidateSet('WorkspaceSettings', 'ContentHub', 'CustomContent', 'DefenderDetections')]
        [string[]] $Stage,

        [ValidateSet('WorkspaceSettings', 'ContentHub', 'CustomContent', 'DefenderDetections')]
        [string[]] $ExcludeStage,

        [string[]] $Solution,

        [ValidateSet('High', 'Medium', 'Low', 'Informational')]
        [string[]] $Severity = @('High', 'Medium', 'Low', 'Informational'),

        [switch] $DisableRules,

        [switch] $OverwriteCustomisedRules,

        [switch] $ForceSolutionUpdate,

        [switch] $ForceContentDeployment,

        [ValidateSet('Solution', 'AnalyticsRule', 'Workbook', 'AutomationRule', 'HuntingQuery')]
        [string[]] $ExcludeSolutionContentType,

        [SupportsWildcards()]
        [string[]] $ExcludeContentType,

        [SupportsWildcards()]
        [string[]] $Exclude,

        [switch] $SmartDeployment,

        [psobject] $Context,

        [string] $RepoPath
    )

    $started = Get-Date
    $ctx = Resolve-iSOCContext -Context $Context
    $repo = Resolve-iSOCRepoPath -RepoPath $RepoPath
    $stages = @(Get-iSOCWorkspaceStage)
    $selected = @($stages | Where-Object { (-not $Stage -or $Stage -contains $_.Name) -and $ExcludeStage -notcontains $_.Name } | ForEach-Object { $_.Name })
    $solutions = @($Solution | Where-Object { $_ -and $_.Trim() } | ForEach-Object { $_.Trim() })
    if ($selected -contains 'ContentHub' -and $solutions.Count -eq 0) {
        throw 'The ContentHub stage needs -Solution, the Content Hub solutions to install. Name them, or leave the stage out with -ExcludeStage ContentHub.'
    }

    $settings = @{
        Solution                   = $solutions
        Severity                   = $Severity
        DisableRules               = [bool]$DisableRules
        OverwriteCustomisedRules   = [bool]$OverwriteCustomisedRules
        ForceSolutionUpdate        = [bool]$ForceSolutionUpdate
        ForceContentDeployment     = [bool]$ForceContentDeployment
        ExcludeSolutionContentType = $ExcludeSolutionContentType
        ExcludeContentType         = $ExcludeContentType
        Exclude                    = $Exclude
        SmartDeployment            = [bool]$SmartDeployment
        Context                    = $ctx
        RepoPath                   = $repo
    }

    Write-iSOCLog ('=' * 60)
    Write-iSOCLog "  Workspace deployment to $($ctx.WorkspaceName)" -Level Section
    Write-iSOCLog ('=' * 60)
    Write-iSOCLog "  Stages: $($selected -join ', ')"

    $outcomes = @{}
    $results = [System.Collections.Generic.List[object]]::new()
    $number = 0
    foreach ($entry in $stages) {
        $result = if ($selected -notcontains $entry.Name) {
            @{ Outcome = 'Excluded'; Reason = 'left out'; ExitCode = 0; Run = $null }
        } elseif ($entry.Gate -and $outcomes[$entry.Gate] -eq 'Failed') {
            Write-iSOCLog "Not deploying $($entry.DisplayName): the $($entry.Gate) stage failed." -Level Warning
            @{ Outcome = 'NotRun'; Reason = "the $($entry.Gate) stage failed"; ExitCode = 0; Run = $null }
        } else {
            $number++
            Write-iSOCLog ''
            Write-iSOCLog "Stage $number of $($selected.Count): $($entry.DisplayName)" -Level Section
            Invoke-iSOCWorkspaceStage -Stage $entry.Name -Settings $settings
        }
        $outcomes[$entry.Name] = $result.Outcome
        $results.Add([pscustomobject]@{
                PSTypeName = 'iSOCDeployments.StageResult'
                Stage      = $entry.Name
                Outcome    = $result.Outcome
                Reason     = $result.Reason
                ExitCode   = $result.ExitCode
                Run        = $result.Run
            })
    }

    $failed = @($results | Where-Object { $_.Outcome -eq 'Failed' }).Count
    Write-iSOCLog ''
    Write-iSOCLog 'Workspace deployment summary' -Level Section
    foreach ($result in $results) {
        $why = if ($result.Reason) { " ($($result.Reason))" } else { '' }
        Write-iSOCLog ('  {0,-20} {1}{2}' -f $result.Stage, $result.Outcome, $why) -Level $(if ($result.Outcome -eq 'Failed') { 'Error' } else { 'Info' })
    }

    [pscustomobject]@{
        PSTypeName = 'iSOCDeployments.WorkspaceDeployRun'
        Stages     = $results.ToArray()
        Failed     = $failed
        Duration   = (Get-Date) - $started
        ExitCode   = $(if ($failed -gt 0) { 1 } else { 0 })
    }
}

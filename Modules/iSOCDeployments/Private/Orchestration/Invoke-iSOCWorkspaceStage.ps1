#Requires -Version 7.6

<#
.SYNOPSIS
    Run one stage of Deploy-iSOCWorkspace.

.DESCRIPTION
    Copied from the stage steps of Pipelines/Sentinel-Deploy.yml and
    .github/workflows/sentinel-deploy.yml: the Configure Sentinel Settings
    step, the Content Hub step, the dependency manifest guard and custom
    content step, and the Defender step, each calling the module's command
    in place of its script.

.NOTES
    File:         Modules/iSOCDeployments/Private/Orchestration/Invoke-iSOCWorkspaceStage.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-05
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Invoke-iSOCWorkspaceStage {
    <#
    .SYNOPSIS
        Run one stage of Deploy-iSOCWorkspace and say how it went.

    .DESCRIPTION
        - WorkspaceSettings: Deploy-iSOCContent -ContentType WorkspaceSetting.
        - ContentHub: Install-iSOCContentHubSolution with the solutions,
          severities and switches given.
        - CustomContent: Test-iSOCDependencyManifest first, as the pipelines'
          guard step did; a manifest that is missing or out of date fails the
          stage without deploying anything. Then Deploy-iSOCContent for every
          type but the workspace settings and the Defender detections, which
          have stages of their own, and those -ExcludeContentType names.
        - DefenderDetections: Deploy-iSOCContent -ContentType
          DefenderDetection.

        -WhatIf reaches every command, and -SmartDeployment and -Exclude
        every Deploy-iSOCContent call. The stage fails when its command's
        ExitCode is not 0; an error the command throws fails the stage too,
        with its message as the reason, rather than stopping the run.

    .PARAMETER Stage
        The stage name, from Get-iSOCWorkspaceStage.

    .PARAMETER Settings
        Deploy-iSOCWorkspace's parameters: Solution, Severity, DisableRules,
        OverwriteCustomisedRules, ForceSolutionUpdate,
        ForceContentDeployment, ExcludeSolutionContentType,
        ExcludeContentType, Exclude, SmartDeployment, Context and RepoPath.

    .OUTPUTS
        [hashtable] Outcome (Succeeded or Failed), Reason, ExitCode and Run
        (the command's result, when it returned one).

    .EXAMPLE
        $result = Invoke-iSOCWorkspaceStage -Stage ContentHub -Settings $settings
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'The stage commands ask ShouldProcess for each write; this passes -WhatIf on to them.')]
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('WorkspaceSettings', 'ContentHub', 'CustomContent', 'DefenderDetections')]
        [string] $Stage,

        [Parameter(Mandatory)]
        [hashtable] $Settings
    )

    $list = { param($Value) , @($Value | Where-Object { $null -ne $_ -and [string]$_ -ne '' }) }
    $deploy = @{
        Context         = $Settings.Context
        RepoPath        = $Settings.RepoPath
        SmartDeployment = [bool]$Settings.SmartDeployment
        WhatIf          = [bool]$WhatIfPreference
    }
    $exclude = & $list $Settings.Exclude
    if ($exclude.Count -gt 0) { $deploy.Exclude = $exclude }

    try {
        $run = switch ($Stage) {
            'WorkspaceSettings' { Deploy-iSOCContent -ContentType WorkspaceSetting @deploy }
            'ContentHub' {
                $hub = @{
                    Name                     = & $list $Settings.Solution
                    Severity                 = & $list $Settings.Severity
                    DisableRules             = [bool]$Settings.DisableRules
                    OverwriteCustomisedRules = [bool]$Settings.OverwriteCustomisedRules
                    ForceSolutionUpdate      = [bool]$Settings.ForceSolutionUpdate
                    ForceContentDeployment   = [bool]$Settings.ForceContentDeployment
                    ExcludeContentType       = & $list $Settings.ExcludeSolutionContentType
                    Context                  = $Settings.Context
                    WhatIf                   = [bool]$WhatIfPreference
                }
                Install-iSOCContentHubSolution @hub
            }
            'CustomContent' {
                $manifest = Test-iSOCDependencyManifest -RepoPath $Settings.RepoPath
                if (-not $manifest.Exists -or $manifest.HasDrift) {
                    Write-iSOCLog 'dependencies.json is out of sync. Refusing to deploy with a stale dependency graph.' -Level Error
                    Write-iSOCLog 'Fix: run Update-iSOCDependencyManifest, commit, then run the deployment again.' -Level Error
                    return @{ Outcome = 'Failed'; Reason = 'dependencies.json is out of sync with the content'; ExitCode = 1; Run = $manifest }
                }
                $excluded = @((& $list $Settings.ExcludeContentType) + @('WorkspaceSetting', 'DefenderDetection') | Select-Object -Unique)
                Deploy-iSOCContent -ExcludeContentType $excluded @deploy
            }
            'DefenderDetections' { Deploy-iSOCContent -ContentType DefenderDetection @deploy }
        }
    }
    catch {
        Write-iSOCLog "The $Stage stage stopped: $($_.Exception.Message)" -Level Error
        return @{ Outcome = 'Failed'; Reason = $_.Exception.Message; ExitCode = 1; Run = $null }
    }

    $exitCode = [int](Get-iSOCPropertyValue -InputObject $run -Path 'ExitCode')
    if ($exitCode -ne 0) { return @{ Outcome = 'Failed'; Reason = 'some items failed'; ExitCode = $exitCode; Run = $run } }
    @{ Outcome = 'Succeeded'; Reason = ''; ExitCode = 0; Run = $run }
}

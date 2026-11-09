#Requires -Version 7.6

<#
.SYNOPSIS
    The stages Deploy-iSOCWorkspace runs, in order, and which stage gates
    each.

.DESCRIPTION
    Copied from the stage order and the stage conditions of
    Pipelines/Sentinel-Deploy.yml and .github/workflows/sentinel-deploy.yml,
    after the infrastructure stage.

.NOTES
    File:         Modules/iSOCDeployments/Private/Orchestration/Get-iSOCWorkspaceStage.ps1
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

function Get-iSOCWorkspaceStage {
    <#
    .SYNOPSIS
        Return the stages Deploy-iSOCWorkspace runs, in order.

    .DESCRIPTION
        Each stage names the stage that gates it, as the pipelines' stage
        conditions do: a stage does not run when its gate failed, and runs
        when its gate succeeded, was left out or did not run itself. So a
        failed Content Hub stage holds back custom content, while the
        Defender detections, gated by custom content, still run. Workspace
        settings gate nothing: the pipelines configured them in the
        infrastructure stage and only warned when one failed.

    .OUTPUTS
        [pscustomobject] Name, Gate (the stage name, or null), and
        DisplayName.

    .EXAMPLE
        Get-iSOCWorkspaceStage | Select-Object Name, Gate
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    [pscustomobject]@{ Name = 'WorkspaceSettings'; Gate = $null; DisplayName = 'workspace settings' }
    [pscustomobject]@{ Name = 'ContentHub'; Gate = $null; DisplayName = 'Content Hub solutions' }
    [pscustomobject]@{ Name = 'CustomContent'; Gate = 'ContentHub'; DisplayName = 'custom content' }
    [pscustomobject]@{ Name = 'DefenderDetections'; Gate = 'CustomContent'; DisplayName = 'Defender XDR custom detections' }
}

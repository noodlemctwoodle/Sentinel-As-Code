#Requires -Version 7.2

<#
.SYNOPSIS
    The state one Deploy-iSOCContent call works with.

.DESCRIPTION
    Replaces the script-scope variables Deploy-CustomContent.ps1 kept
    (DeploymentConfig, ChangedFiles, DeploymentState, DependencyGraph and
    the workspace lists). Each call builds its own run and passes it down,
    so nothing carries over between calls.

.NOTES
    File:         Modules/iSOCDeployments/Private/Deploy/New-iSOCDeployRun.ps1
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

function New-iSOCDeployRun {
    <#
    .SYNOPSIS
        Build a deployment run.

    .PARAMETER Context
        The workspace context.

    .PARAMETER RepoPath
        The repository root.

    .PARAMETER Config
        From Get-iSOCDeploymentConfig.

    .PARAMETER ChangedFiles
        From Get-iSOCChangedFile; nothing for a full deployment.

    .PARAMETER State
        From Read-iSOCDeploymentState.

    .PARAMETER Graph
        From Read-iSOCDependencyGraph.

    .OUTPUTS
        [pscustomobject] Context, RepoPath, Config, ChangedFiles, State,
        Graph, Inventory (set by the pre-flight checks), Results (a list of
        item results) and Started.

    .EXAMPLE
        $run = New-iSOCDeployRun -Context $ctx -RepoPath $repo -Config $config -State $state -Graph $graph
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds an object in memory; nothing outside the call changes.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Context,

        [Parameter(Mandatory)]
        [string] $RepoPath,

        [Parameter(Mandatory)]
        [psobject] $Config,

        [AllowNull()]
        [string[]] $ChangedFiles,

        [Parameter(Mandatory)]
        [psobject] $State,

        [Parameter(Mandatory)]
        [hashtable] $Graph
    )

    [pscustomobject]@{
        PSTypeName   = 'iSOCDeployments.DeployState'
        Context      = $Context
        RepoPath     = $RepoPath
        Config       = $Config
        ChangedFiles = $ChangedFiles
        State        = $State
        Graph        = $Graph
        Inventory    = [pscustomobject]@{ Tables = $null; Watchlists = $null; Functions = $null; RepoFunctions = @(); RepoWatchlists = @() }
        Results      = [System.Collections.Generic.List[object]]::new()
        Started      = Get-Date
    }
}

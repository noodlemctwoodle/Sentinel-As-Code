#Requires -Version 7.2

<#
.SYNOPSIS
    Read sentinel-deployment.config: deploy priorities and exclusions.

.DESCRIPTION
    Replaces the config loader in Initialize-SmartDeployment
    (Deploy/content/Deploy-CustomContent.ps1). The file is read from the
    repository root, where it moves at the 26.11.0 cut-over, and from
    Deploy/content/ until then (MIGRATION.md edit E11).

.NOTES
    File:         Modules/iSOCDeployments/Private/Deploy/Get-iSOCDeploymentConfig.ps1
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

function Get-iSOCDeploymentConfig {
    <#
    .SYNOPSIS
        Return the deployment configuration, or an empty one.

    .DESCRIPTION
        prioritizedcontentfiles lists paths (or path prefixes) that deploy
        first within their content type; excludecontentfiles lists paths
        (or prefixes) that never deploy. A file that does not parse is
        reported and treated as empty, as the script did.

    .PARAMETER RepoPath
        The repository root.

    .OUTPUTS
        [pscustomobject] Path (repository-relative, or nothing),
        Prioritized and Excluded (string arrays) and ParameterFileMappings.

    .EXAMPLE
        $config = Get-iSOCDeploymentConfig -RepoPath $repo
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $RepoPath
    )

    $config = [pscustomobject]@{ Path = $null; Prioritized = @(); Excluded = @(); ParameterFileMappings = $null }
    $candidates = @(
        (Join-Path $RepoPath 'sentinel-deployment.config')
        (Join-Path $RepoPath (Join-Path 'Deploy' (Join-Path 'content' 'sentinel-deployment.config')))
    )
    $path = $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    if (-not $path) { return $config }

    $config.Path = ConvertTo-iSOCRepoRelativePath -Path $path -RepoPath $RepoPath
    try {
        $raw = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-iSOCLog "Failed to parse $($config.Path): $($_.Exception.Message)" -Level Warning
        return $config
    }

    Write-iSOCLog "Loaded $($config.Path)"
    # Assigned first: the helper returns a list as one object, so piping it
    # straight on would nest it.
    $prioritized = Get-iSOCPropertyValue -InputObject $raw -Path 'prioritizedcontentfiles'
    $excluded = Get-iSOCPropertyValue -InputObject $raw -Path 'excludecontentfiles'
    $config.Prioritized = @($prioritized | Where-Object { $_ } | ForEach-Object { [string]$_ })
    $config.Excluded = @($excluded | Where-Object { $_ } | ForEach-Object { [string]$_ })
    $config.ParameterFileMappings = Get-iSOCPropertyValue -InputObject $raw -Path 'parameterfilemappings'
    if ($config.Excluded.Count -gt 0) { Write-iSOCLog "  Excluded paths: $($config.Excluded -join ', ')" }
    if ($config.Prioritized.Count -gt 0) { Write-iSOCLog "  Prioritized files: $($config.Prioritized -join ', ')" }
    $config
}

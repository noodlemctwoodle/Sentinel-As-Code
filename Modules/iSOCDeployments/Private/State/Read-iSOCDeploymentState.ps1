#Requires -Version 7.6

<#
.SYNOPSIS
    Read deployment-state.json, the record of what deployed successfully.

.DESCRIPTION
    Replaces Initialize-DeploymentState (Deploy/content/Deploy-CustomContent.ps1).
    The file and its format are the same, so a state file the script wrote
    carries over. A pipeline that downloads the state as a build artifact
    gets it in a deployment-state/ subfolder; the script copied it to the
    root, and this reads it where it is (MIGRATION.md edit E12).

.NOTES
    File:         Modules/iSOCDeployments/Private/State/Read-iSOCDeploymentState.ps1
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

function Read-iSOCDeploymentState {
    <#
    .SYNOPSIS
        Return the deployment state, empty when there is none.

    .DESCRIPTION
        Items maps each content file's repository-relative path to its last
        successful deployment (lastDeployed, status). Smart deployment
        retries anything not recorded as a success. A file that does not
        parse is reported and treated as empty.

    .PARAMETER RepoPath
        The repository root.

    .OUTPUTS
        [pscustomobject] Path (the file to save to, at the root) and Items
        (a hashtable).

    .EXAMPLE
        $state = Read-iSOCDeploymentState -RepoPath $repo
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $RepoPath
    )

    $state = [pscustomobject]@{ Path = Join-Path $RepoPath 'deployment-state.json'; Items = @{} }
    $artifact = Join-Path $RepoPath (Join-Path 'deployment-state' 'deployment-state.json')
    $source = if (Test-Path -LiteralPath $state.Path -PathType Leaf) { $state.Path } elseif (Test-Path -LiteralPath $artifact -PathType Leaf) { $artifact } else { $null }

    if (-not $source) {
        Write-iSOCLog 'No deployment state file found; all items will deploy on first run.'
        return $state
    }

    try {
        $raw = Get-Content -LiteralPath $source -Raw | ConvertFrom-Json -ErrorAction Stop
        $items = Get-iSOCPropertyValue -InputObject $raw -Path 'deployedItems'
        if ($items) {
            foreach ($property in $items.PSObject.Properties) {
                $state.Items[$property.Name] = @{
                    lastDeployed = Get-iSOCPropertyValue -InputObject $property.Value -Path 'lastDeployed'
                    status       = Get-iSOCPropertyValue -InputObject $property.Value -Path 'status'
                }
            }
        }
        Write-iSOCLog "Loaded deployment state: $($state.Items.Count) previously deployed item(s)."
    }
    catch {
        Write-iSOCLog "Failed to load deployment state: $($_.Exception.Message); starting fresh." -Level Warning
        $state.Items = @{}
    }
    $state
}

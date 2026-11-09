#Requires -Version 7.6

<#
.SYNOPSIS
    Pre-flight: what the workspace already has, for the dependency checks.

.DESCRIPTION
    Replaces Invoke-PreFlightChecks (Deploy/content/Deploy-CustomContent.ps1).
    Two faults are fixed (MIGRATION.md edit E13): the stale-state check
    counted state entries starting AnalyticalRules/, which no entry has
    since content moved under Content/, so it never fired; and when a list
    could not be read the script said its checks would be skipped but then
    treated every such dependency as missing. A list that cannot be read now
    skips the checks that need it.

.NOTES
    File:         Modules/iSOCDeployments/Private/Deploy/Get-iSOCWorkspaceInventory.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    Needs powershell-yaml when it runs. Import-iSOCYamlModule loads it
    then instead of #Requires, so the module imports without it.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCWorkspaceInventory {
    <#
    .SYNOPSIS
        Read the workspace's tables, watchlists and functions, and the
        repository's own parsers and watchlists.

    .DESCRIPTION
        One list request each: tables, watchlists (not deleted) and saved
        searches with a function alias. When the state records more than ten
        analytics rules deployed but the workspace has none, the state is
        stale (the workspace was rebuilt) and is reset, so everything
        deploys again. A dependency is met by the workspace or by the
        repository content this run deploys.

    .PARAMETER Run
        The deployment run. Its State may be reset.

    .OUTPUTS
        [pscustomobject] Tables, Watchlists and Functions (what the
        workspace has; nothing when a list could not be read) and
        RepoFunctions and RepoWatchlists (what the repository deploys).

    .EXAMPLE
        $run.Inventory = Get-iSOCWorkspaceInventory -Run $run
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Run
    )

    Write-iSOCLog 'Running pre-flight dependency checks...' -Level Section
    $workspace = $Run.Context.WorkspaceResourceId

    if ($Run.State.Items.Count -gt 0) {
        try {
            $rules = @(Invoke-iSOCRestRequest -Method GET -Path "$workspace/providers/Microsoft.SecurityInsights/alertRules" -ApiVersion (Get-iSOCApiVersion SecurityInsightsPreview))
            $stateRuleCount = @($Run.State.Items.Keys | Where-Object { $_ -like 'Content/AnalyticalRules/*' }).Count
            if ($stateRuleCount -gt 10 -and $rules.Count -eq 0) {
                Write-iSOCLog "Deployment state claims $stateRuleCount rules deployed but workspace has 0; state is stale. Resetting." -Level Warning
                $Run.State.Items = @{}
            }
        }
        catch {
            Write-iSOCLog "  Could not validate deployment state against workspace: $($_.Exception.Message)" -Level Warning
        }
    }

    $read = {
        param([string] $Label, [string] $Path, [string] $ApiVersion, [scriptblock] $Select)
        try {
            $found = @(Invoke-iSOCRestRequest -Method GET -Path $Path -ApiVersion $ApiVersion | ForEach-Object $Select | Where-Object { $_ })
            Write-iSOCLog "  Workspace has $($found.Count) $Label."
            , $found
        }
        catch {
            Write-iSOCLog "  Failed to list workspace ${Label}: $($_.Exception.Message)" -Level Warning
            Write-iSOCLog "  Dependency checks on $Label will be skipped." -Level Warning
            $null
        }
    }

    $tables = & $read 'tables' "$workspace/tables" (Get-iSOCApiVersion OperationalInsights) { $_.name }
    $watchlists = & $read 'watchlists' "$workspace/providers/Microsoft.SecurityInsights/watchlists" (Get-iSOCApiVersion SecurityInsights) {
        $properties = Get-iSOCPropertyValue -InputObject $_ -Path 'properties'
        if ($properties -and -not (Get-iSOCPropertyValue -InputObject $properties -Path 'isDeleted')) { Get-iSOCPropertyValue -InputObject $properties -Path 'watchlistAlias' }
    }
    $functions = & $read 'functions/parsers' "$workspace/savedSearches" (Get-iSOCApiVersion SavedSearches) {
        Get-iSOCPropertyValue -InputObject $_ -Path 'properties.functionAlias'
    }

    $repo = Get-iSOCDependencyInventory -RepoPath $Run.RepoPath
    $repoFunctions = @($repo.Functions.Keys | Sort-Object)
    $repoWatchlists = @($repo.Watchlists.Keys | Where-Object { $_ } | Sort-Object)
    Write-iSOCLog "  Internal parsers to deploy: $($repoFunctions -join ', ')"
    Write-iSOCLog "  Internal watchlists to deploy: $($repoWatchlists -join ', ')"
    Write-iSOCLog 'Pre-flight checks complete.' -Level Success

    [pscustomobject]@{
        Tables         = $tables
        Watchlists     = $watchlists
        Functions      = $functions
        RepoFunctions  = $repoFunctions
        RepoWatchlists = $repoWatchlists
    }
}

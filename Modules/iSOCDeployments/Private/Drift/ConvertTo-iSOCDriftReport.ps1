#Requires -Version 7.2

<#
.SYNOPSIS
    A compare's result in the drift report's shape.

.DESCRIPTION
    Replaces the report the end of Invoke-Main built
    (Tools/Test-SentinelRuleDrift.ps1), in the same shape, so the reports the
    drift bot commits read as before. Each rule is named by its name (its
    id in the workspace); the script also gave its full resource id, which
    holds the subscription id (MIGRATION.md edit E24).

.NOTES
    File:         Modules/iSOCDeployments/Private/Drift/ConvertTo-iSOCDriftReport.ps1
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

function ConvertTo-iSOCDriftReport {
    <#
    .SYNOPSIS
        Return the report: when, where, the summary, the drifted rules and
        the orphans.

    .DESCRIPTION
        drifted lists the rules changed in the workspace (PortalEdit and
        ContentHubCustomised), each with its changed fields; orphans the
        rules only the workspace has (PortalOnly). Once Sync-iSOCContent has
        run, a drifted rule says whether its file changed (yamlUpdated) and
        an absorbed one where it was written (absorbedPath, absorbedAction).
        Paths are repository-relative.

    .PARAMETER Drift
        From Compare-iSOCContent, after Sync-iSOCContent when it ran.

    .OUTPUTS
        [System.Collections.Specialized.OrderedDictionary] generatedAt,
        workspace, resourceGroup, summary, drifted and orphans.

    .EXAMPLE
        $report = ConvertTo-iSOCDriftReport -Drift $drift
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Drift
    )

    $lower = { param([string] $Action) if ($Action) { $Action.ToLowerInvariant() } }
    $drifted = foreach ($item in @($Drift.Items | Where-Object { $_.State -in 'PortalEdit', 'ContentHubCustomised' })) {
        $entry = [ordered]@{
            ruleName       = $item.ResourceName
            displayName    = $item.Name
            kind           = $item.Kind
            source         = $item.Source
            sourceRef      = $item.SourceRef
            solution       = $item.Solution
            modifiedFields = @($item.Modifications | ForEach-Object { [ordered]@{ field = $_.Field; deployed = $_.Deployed; expected = $_.Expected } })
        }
        if ($item.SyncAction) {
            $entry.yamlUpdated = $item.SyncAction -in 'Updated', 'Created'
            if ($item.Source -eq 'ContentHub' -and $item.SyncPath) {
                $entry.absorbedPath = $item.SyncPath
                $entry.absorbedAction = & $lower $item.SyncAction
            }
        }
        $entry
    }
    $orphans = foreach ($item in @($Drift.Items | Where-Object { $_.State -eq 'PortalOnly' })) {
        $entry = [ordered]@{
            ruleName    = $item.ResourceName
            displayName = $item.Name
            kind        = $item.Kind
            enabled     = $item.Enabled
        }
        if ($item.SyncPath) {
            $entry.absorbedPath = $item.SyncPath
            $entry.absorbedAction = & $lower $item.SyncAction
        }
        $entry
    }

    [ordered]@{
        generatedAt   = $Drift.GeneratedAt
        workspace     = $Drift.Workspace
        resourceGroup = $Drift.ResourceGroup
        summary       = $Drift.Summary
        drifted       = @($drifted)
        orphans       = @($orphans)
    }
}

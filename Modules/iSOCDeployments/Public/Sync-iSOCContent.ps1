#Requires -Version 7.6

<#
.SYNOPSIS
    Sync-iSOCContent: write what drifted in the workspace into the
    repository.

.DESCRIPTION
    The absorb half of Tools/Test-SentinelRuleDrift.ps1. The script absorbed
    unless -ReportOnly was given; here absorbing is this command, run on a
    Compare-iSOCContent result or left out (MIGRATION.md edit E24).

.NOTES
    File:         Modules/iSOCDeployments/Public/Sync-iSOCContent.ps1
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

function Sync-iSOCContent {
    <#
    .SYNOPSIS
        Absorb the workspace's changes into the repository, so the next
        deploy keeps them.

    .DESCRIPTION
        For each drifted item of a Compare-iSOCContent result:

        - PortalEdit: the item's repository file is rewritten in place with
          the workspace's values for the fields that changed, and its patch
          version raised; everything else in the file is left as it was;
        - ContentHubCustomised: the item is written to a new repository file
          (for analytics rules under
          Content/AnalyticalRules/AbsorbedFromPortal/ContentHub/<solution>/)
          that keeps its id, so the next deploy governs it from the
          repository instead of the template;
        - PortalOnly: the item is exported the same way (under
          Content/AnalyticalRules/AbsorbedFromPortal/Orphans/).

        Once absorbed, an item is governed by its file, and later portal
        changes are written back to the same file. A file whose content
        would not change is left alone, so a run that finds the same drift
        again leaves the working tree clean. Nothing is ever deleted, and
        the workspace is not touched. Each item records what was done
        (SyncAction: Updated, Created, Unchanged, NoMatch when a field had
        no line to replace, or Failed) and the file (SyncPath); pass the
        result on to Export-iSOCDriftReport. With -WhatIf nothing is
        written.

    .PARAMETER InputObject
        A Compare-iSOCContent result.

    .OUTPUTS
        [pscustomobject] The same iSOCDeployments.DriftResult, its items
        updated.

    .EXAMPLE
        Compare-iSOCContent | Sync-iSOCContent | Export-iSOCDriftReport

        Finds the drift, writes it into the repository and writes the
        report, as the drift pipeline does.

    .EXAMPLE
        $drift = Compare-iSOCContent
        $drift | Sync-iSOCContent -WhatIf

        Shows which files the drift would change, writing none.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('iSOCDeployments.DriftResult')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [psobject] $InputObject
    )

    process {
        $repo = $InputObject.RepoPath
        foreach ($item in @($InputObject.Items)) {
            if ($item.State -notin 'PortalEdit', 'ContentHubCustomised', 'PortalOnly') { continue }
            $type = Get-iSOCContentTypeDefinition -Name $item.ContentType
            if ($type.Capabilities -notcontains 'Sync') { continue }

            if ($item.State -eq 'PortalEdit') {
                if (-not $PSCmdlet.ShouldProcess($item.SourceRef, "Write the workspace's changes to $($item.Name)")) { continue }
                try {
                    $changed = Invoke-iSOCContentTypeHandler -ContentType $type -Handler UpdateRepoFile -Parameters @{ Path = $item.SourcePath; Modification = $item.Modifications }
                    $item.SyncPath = $item.SourceRef
                    if ($changed) {
                        $item.SyncAction = 'Updated'
                        Write-iSOCLog "  Synced YAML: $($item.SourceRef)" -Level Success
                    } else {
                        $item.SyncAction = 'NoMatch'
                        Write-iSOCLog "  No-op on YAML: $($item.SourceRef) (regex did not match; manual edit required)" -Level Warning
                    }
                } catch {
                    $item.SyncAction = 'Failed'
                    Write-iSOCLog "  Failed to update '$($item.SourceRef)': $($_.Exception.Message)" -Level Error
                }
                continue
            }

            $provenance = if ($item.State -eq 'ContentHubCustomised') { 'ContentHub' } else { 'Orphan' }
            $verb = if ($provenance -eq 'ContentHub') { 'promote' } else { 'absorb orphan' }
            try {
                $path = Invoke-iSOCContentTypeHandler -ContentType $type -Handler GetRepoPath -Parameters @{ WorkspaceItem = $item.WorkspaceItem; Provenance = $provenance; SolutionName = $item.Solution }
                if (-not $PSCmdlet.ShouldProcess($path, "Write $($item.Name) from the workspace")) { continue }
                $content = Invoke-iSOCContentTypeHandler -ContentType $type -Handler ToRepoFile -Parameters @{ WorkspaceItem = $item.WorkspaceItem; Provenance = $provenance; SolutionName = $item.Solution }
                $item.SyncAction = Save-iSOCRepoFile -RepoPath $repo -RelativePath $path -Content $content
                $item.SyncPath = $path
                $message = if ($provenance -eq 'ContentHub') { 'Promoted ContentHub drift to Custom YAML' } else { 'Absorbed orphan into Custom YAML' }
                Write-iSOCLog "  $message ($($item.SyncAction.ToLowerInvariant())): $path" -Level Success
            } catch {
                $item.SyncAction = 'Failed'
                Write-iSOCLog "  Failed to $verb '$($item.Name)': $($_.Exception.Message)" -Level Error
            }
        }
        $InputObject
    }
}

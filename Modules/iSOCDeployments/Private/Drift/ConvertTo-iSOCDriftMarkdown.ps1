#Requires -Version 7.2

<#
.SYNOPSIS
    A drift report as Markdown, for the pull request the drift bot opens.

.DESCRIPTION
    Copied from the Markdown half of Write-DriftReport
    (Tools/Test-SentinelRuleDrift.ps1). Each section says what was done: the
    script called the Custom rules auto-synced even under -ReportOnly, and
    the Content Hub and orphan rules report-only even when it had written
    them into the repository (MIGRATION.md edit E24).

.NOTES
    File:         Modules/iSOCDeployments/Private/Drift/ConvertTo-iSOCDriftMarkdown.ps1
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

function ConvertTo-iSOCDriftMarkdown {
    <#
    .SYNOPSIS
        Return the report's Markdown.

    .DESCRIPTION
        The summary table, then a section each for Custom rules changed in
        the portal, Content Hub rules changed from their template, and
        orphan rules, each rule with its changed fields
        (Format-iSOCDriftFieldBlock). A section says whether its rules were
        written into the repository, and where.

    .PARAMETER Report
        From ConvertTo-iSOCDriftReport.

    .OUTPUTS
        [string]

    .EXAMPLE
        ConvertTo-iSOCDriftMarkdown -Report $report
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Report
    )

    $summary = $Report.summary
    $has = { param($Entry, [string] $Key) $Entry.Contains($Key) }
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('# Sentinel Analytics Rule Drift Report')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("- Generated: $($Report.generatedAt)")
    [void]$sb.AppendLine("- Resource Group: $($Report.resourceGroup)")
    [void]$sb.AppendLine("- Workspace: $($Report.workspace)")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## Summary')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('| Bucket | Count |')
    [void]$sb.AppendLine('| --- | ---: |')
    foreach ($row in @(
            @('Total deployed', 'totalDeployed'), @('Content Hub clean', 'contentHubClean'), @('Content Hub drift', 'contentHubDrift'),
            @('Custom clean', 'customClean'), @('Custom drift', 'customDrift'), @('Orphan', 'orphan'), @('Managed (excluded)', 'managed'))) {
        [void]$sb.AppendLine("| $($row[0]) | $($summary[$row[1]]) |")
    }

    $customDrifted = @($Report.drifted | Where-Object { $_.source -eq 'Custom' })
    $contentHubDrifted = @($Report.drifted | Where-Object { $_.source -eq 'ContentHub' })

    if ($customDrifted.Count -gt 0) {
        $synced = @($customDrifted | Where-Object { & $has $_ 'yamlUpdated' }).Count -gt 0
        [void]$sb.AppendLine('')
        if ($synced) {
            [void]$sb.AppendLine('## Custom Rule Drift (auto-synced into repo)')
            [void]$sb.AppendLine('')
            [void]$sb.AppendLine('These rules were edited in the Sentinel portal. The matching YAML files under `Content/AnalyticalRules/` have been updated to reflect the deployed state. Compare against the **Files Changed** tab of this PR to see the YAML diff exactly as committed.')
        }
        else {
            [void]$sb.AppendLine('## Custom Rule Drift (report only)')
            [void]$sb.AppendLine('')
            [void]$sb.AppendLine('These rules were edited in the Sentinel portal. Their YAML files under `Content/AnalyticalRules/` have not been changed; run `Sync-iSOCContent` to write the deployed state into them.')
        }
        foreach ($d in $customDrifted) {
            [void]$sb.AppendLine('')
            [void]$sb.AppendLine("### $($d.displayName)")
            [void]$sb.AppendLine('')
            [void]$sb.AppendLine("- File: ``$($d.sourceRef)``")
            [void]$sb.AppendLine("- Rule GUID: ``$($d.ruleName)``")
            [void]$sb.AppendLine("- Kind: $($d.kind)")
            if (& $has $d 'yamlUpdated') { [void]$sb.AppendLine("- YAML updated: $($d.yamlUpdated)") }
            [void]$sb.AppendLine('')
            [void]$sb.AppendLine('#### Modified fields')
            $deployedLabel = if ($synced) { 'Deployed (now in YAML)' } else { 'Deployed' }
            foreach ($m in $d.modifiedFields) { [void]$sb.Append((Format-iSOCDriftFieldBlock -Modification ([pscustomobject]$m) -DeployedLabel $deployedLabel -ExpectedLabel 'Previously in YAML')) }
        }
    }

    if ($contentHubDrifted.Count -gt 0) {
        $promoted = @($contentHubDrifted | Where-Object { & $has $_ 'absorbedPath' }).Count -gt 0
        [void]$sb.AppendLine('')
        if ($promoted) {
            [void]$sb.AppendLine('## Content Hub Drift (promoted to Custom rules)')
            [void]$sb.AppendLine('')
            [void]$sb.AppendLine('These rules diverge from their Content Hub template. Each has been written to a Custom rule file under `Content/AnalyticalRules/AbsorbedFromPortal/ContentHub/` that keeps its rule id, so the next deploy governs it from the repository instead of the template.')
        }
        else {
            [void]$sb.AppendLine('## Content Hub Drift (report only)')
            [void]$sb.AppendLine('')
            [void]$sb.AppendLine('These rules diverge from their Content Hub template, and no file has been written for them. Content Hub deployment leaves a rule changed in the workspace alone unless it is told to overwrite it.')
        }
        foreach ($d in $contentHubDrifted) {
            [void]$sb.AppendLine('')
            [void]$sb.AppendLine("### $($d.displayName)")
            [void]$sb.AppendLine('')
            if ($d.solution) { [void]$sb.AppendLine("- Solution: $($d.solution)") }
            if ($d.sourceRef) { [void]$sb.AppendLine("- Template: ``$($d.sourceRef)``") }
            [void]$sb.AppendLine("- Rule GUID: ``$($d.ruleName)``")
            [void]$sb.AppendLine("- Kind: $($d.kind)")
            if (& $has $d 'absorbedPath') { [void]$sb.AppendLine("- Absorbed as: ``$($d.absorbedPath)`` ($($d.absorbedAction))") }
            [void]$sb.AppendLine('')
            [void]$sb.AppendLine('#### Modified fields')
            foreach ($m in $d.modifiedFields) { [void]$sb.Append((Format-iSOCDriftFieldBlock -Modification ([pscustomobject]$m) -DeployedLabel 'Deployed' -ExpectedLabel 'Template')) }
        }
    }

    $orphans = @($Report.orphans)
    if ($orphans.Count -gt 0) {
        $absorbed = @($orphans | Where-Object { & $has $_ 'absorbedPath' }).Count -gt 0
        [void]$sb.AppendLine('')
        if ($absorbed) {
            [void]$sb.AppendLine('## Orphan Rules (absorbed into the repo)')
            [void]$sb.AppendLine('')
            [void]$sb.AppendLine('These rules were created directly in the Sentinel portal and had no source of truth in the repository. Each has been exported to a Custom rule file under `Content/AnalyticalRules/AbsorbedFromPortal/Orphans/`, so the next deploy governs it.')
            [void]$sb.AppendLine('')
            [void]$sb.AppendLine('| Display name | Rule GUID | Kind | Enabled | Absorbed as |')
            [void]$sb.AppendLine('| --- | --- | --- | --- | --- |')
            foreach ($o in $orphans) {
                $path = if (& $has $o 'absorbedPath') { "``$($o.absorbedPath)`` ($($o.absorbedAction))" } else { 'not written' }
                [void]$sb.AppendLine("| $($o.displayName) | $($o.ruleName) | $($o.kind) | $($o.enabled) | $path |")
            }
        }
        else {
            [void]$sb.AppendLine('## Orphan Rules (report only; manual triage required)')
            [void]$sb.AppendLine('')
            [void]$sb.AppendLine('These rules were created directly in the Sentinel portal and have no source-of-truth in the repo. Adopting them into governance is a manual step.')
            [void]$sb.AppendLine('')
            [void]$sb.AppendLine('| Display name | Rule GUID | Kind | Enabled |')
            [void]$sb.AppendLine('| --- | --- | --- | --- |')
            foreach ($o in $orphans) { [void]$sb.AppendLine("| $($o.displayName) | $($o.ruleName) | $($o.kind) | $($o.enabled) |") }
        }
    }

    $sb.ToString()
}

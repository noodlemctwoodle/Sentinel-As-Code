#Requires -Version 7.2

<#
.SYNOPSIS
    Find the classic custom log tables and what depends on each, before migrating them.

.DESCRIPTION
    Get-iSOCTableMigrationImpact replaces the assessment in
    Tools/ClassicToDcr/Invoke-TableMigrationReview.ps1;
    Export-iSOCTableMigrationReport writes its reports.

.NOTES
    File:         Modules/iSOCDeployments/Public/Get-iSOCTableMigrationImpact.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.0
    Last Updated: 2026-11-04
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter and
    per-example detail lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCTableMigrationImpact {
    <#
    .SYNOPSIS
        Find the classic custom log tables and what depends on each, before
        migrating them.

    .DESCRIPTION
        Read-only, so safe against a production workspace. Three steps:

          1. Discover the classic (CLv1) custom log tables, leaving out
             AzureDiagnostics.
          2. Assess each table's dependents across analytics rules, hunting
             queries, parsers, saved searches, workbooks, Logic App
             playbooks and data collection rules. A direct dependent names
             the table; an indirect one reaches it only through one or more
             parser functions, which a search for the table name does not
             find, and carries the chain that explains it. Parser aliases
             that cannot be followed safely are listed with the reason and
             the content that names them, as are chains deeper than
             -MaxParserChainDepth.
          3. Map each table to its Content Hub solutions, from the
             Azure-Sentinel Solutions Analyzer mapping the module ships, and
             classify each solution's data connector (CCF, AzureFunctions,
             AMA, Platform, Agent or Legacy); a Legacy or AzureFunctions
             connector with no CCF version needs rebuilding, not repointing.

        Workbooks, data collection rules and Logic Apps are read from the
        whole subscription. Pipe the result to
        Export-iSOCTableMigrationReport for the CSV, JSON and HTML reports.

    .PARAMETER MaxParserChainDepth
        The most parser hops followed, 1 to 100. Default 10, more than twice
        the deepest parser hierarchy Microsoft ships. A deeper chain is
        reported as truncated rather than dropped.

    .PARAMETER Context
        The workspace, from Connect-iSOCWorkspace. Defaults to the
        connected one.

    .OUTPUTS
        [pscustomobject] An iSOCDeployments.TableMigrationReview: Context
        (SubscriptionId, ResourceGroupName, WorkspaceName), ClassicTables,
        Impacts, SolutionMatches, AliasResolution, DirectCount and
        IndirectCount.

    .EXAMPLE
        Connect-iSOCWorkspace -ResourceGroup rg-sentinel -WorkspaceName law-sentinel
        Get-iSOCTableMigrationImpact | Export-iSOCTableMigrationReport -Path ./migration-report

        Assesses every classic table and writes the reports.

    .EXAMPLE
        (Get-iSOCTableMigrationImpact).Impacts | Where-Object TotalAffected -gt 0 | Select-Object TableName, TotalImpacted, TotalIndirect

        Lists the tables something depends on.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [ValidateRange(1, 100)]
        [int] $MaxParserChainDepth = 10,

        [psobject] $Context
    )

    $ctx = Resolve-iSOCContext -Context $Context
    Assert-iSOCPrerequisite -Step Connect
    $info = [pscustomobject]@{
        SubscriptionId    = $ctx.SubscriptionId
        ResourceGroupName = $ctx.ResourceGroup
        WorkspaceName     = $ctx.WorkspaceName
    }

    Write-iSOCLog 'Step 1: Discover classic custom log tables (CLv1)' -Level Section
    $inventory = Get-iSOCWorkspaceTableInventory -Context $ctx
    $classicTables = @($inventory.ClassicTables)
    $workspaceTableName = @($inventory.AllTableNames)
    $workspaceColumnName = @($inventory.AllColumnNames)

    Write-iSOCLog "Found $($classicTables.Count) classic custom log tables" -Level Success
    if ($classicTables.Count -eq 0) {
        Write-iSOCLog '  Nothing to migrate - workspace has no classic V1 tables.'
        return (New-iSOCTableMigrationReview -Context $info)
    }
    foreach ($t in $classicTables) {
        Write-iSOCLog "  $($t.Name)  plan $($t.Plan), retention $($t.RetentionInDays) days, $($t.ColumnCount) columns"
    }

    Write-iSOCLog 'Step 2: Assess dependency impact' -Level Section
    $content = Read-iSOCTableMigrationContent -Context $ctx
    Write-iSOCLog "  Scanning $($classicTables.Count) tables against:"
    Write-iSOCLog "    Analytics Rules : $($content.AlertRules.Count)"
    Write-iSOCLog "    Hunting Queries : $($content.HuntingQueries.Count)"
    Write-iSOCLog "    Parsers         : $($content.Parsers.Count)"
    Write-iSOCLog "    Saved Searches  : $($content.SavedSearches.Count)"
    Write-iSOCLog "    Workbooks       : $($content.Workbooks.Count)"
    Write-iSOCLog "    Playbooks       : $($content.Playbooks.Count)"
    Write-iSOCLog "    DCRs            : $($content.Dcrs.Count)"

    Write-iSOCLog '  Indexing parser function aliases for chained dependencies...'
    $aliasIndex = Get-iSOCParserAliasIndex -Content $content -WorkspaceTableName $workspaceTableName -WorkspaceColumnName $workspaceColumnName
    Write-iSOCLog "    Workspace tables known    : $($workspaceTableName.Count)"
    Write-iSOCLog "    Parser aliases resolvable : $($aliasIndex.Aliases.Count)"
    if ($aliasIndex.SkippedAliases.Count -gt 0) {
        Write-iSOCLog "$($aliasIndex.SkippedAliases.Count) parser alias(es) are not resolved through chains, to avoid false positives:" -Level Warning
        foreach ($s in $aliasIndex.SkippedAliases) {
            $tail = if ($s.ReferenceCount -gt 0) { " (referenced by $($s.ReferenceCount) item(s), not resolved)" } else { '' }
            Write-iSOCLog "    - $($s.Alias) - $($s.Reason)$tail"
        }
    }
    foreach ($w in $aliasIndex.Warnings) { Write-iSOCLog $w -Level Warning }

    $impacts = [System.Collections.Generic.List[object]]::new()
    foreach ($t in $classicTables) {
        Write-Progress -Activity 'Impact analysis' -Status $t.Name -PercentComplete ((($impacts.Count + 1) / $classicTables.Count) * 100)
        $impacts.Add((Get-iSOCTableImpactAnalysis -TableName $t.Name -Content $content -AliasIndex $aliasIndex -MaxDepth $MaxParserChainDepth))
    }
    Write-Progress -Activity 'Impact analysis' -Completed
    Write-iSOCTableMigrationFinding -Impacts $impacts.ToArray() -TableCount $classicTables.Count -MaxParserChainDepth $MaxParserChainDepth

    Write-iSOCLog 'Step 3: Map to Content Hub solutions (with CCF classification)' -Level Section
    Write-iSOCLog '  Loading Content Hub package catalog...'
    try {
        $packages = @(Read-iSOCContentHubPackage -Context $ctx)
        Write-iSOCLog "Loaded $($packages.Count) Content Hub packages" -Level Success
    }
    catch {
        Write-iSOCLog "Content Hub query failed: $($_.Exception.Message)" -Level Warning
        $packages = @()
    }

    Write-iSOCLog '  Loading static solution mapping (Azure-Sentinel Solutions Analyzer)...'
    $mapping = Get-iSOCSolutionMapping
    if ($mapping) { Write-iSOCLog "Mapping loaded - $($mapping['tableCount']) tables / $($mapping['solutionCount']) solutions" -Level Success }

    $solutionMatches = @(foreach ($t in $classicTables) {
            $match = Get-iSOCSolutionMatch -TableName $t.Name -StaticMapping $mapping -Packages $packages
            $match | Add-Member -NotePropertyName ConnectorClassification `
                -NotePropertyValue @(Get-iSOCConnectorClassification -TableName $t.Name -StaticMapping $mapping -Packages $packages) -PassThru
        })

    $unmatched = @($solutionMatches | Where-Object { $_.MatchCount -eq 0 })
    Write-iSOCLog "Matched $($solutionMatches.Count - $unmatched.Count) of $($solutionMatches.Count) tables" -Level Success
    if ($unmatched.Count -gt 0) {
        Write-iSOCLog "$($unmatched.Count) tables have no Content Hub match - consider raising a feature request with your CSAM/SSP:" -Level Warning
        foreach ($u in $unmatched) { Write-iSOCLog "    - $($u.TableName)" }
    }

    New-iSOCTableMigrationReview -Context $info -ClassicTables $classicTables -Impacts $impacts.ToArray() -SolutionMatches $solutionMatches -AliasResolution ([ordered]@{
            resolvedAliases = @($aliasIndex.Aliases)
            skippedAliases  = @($aliasIndex.SkippedAliases)
            warnings        = @($aliasIndex.Warnings)
        })
}

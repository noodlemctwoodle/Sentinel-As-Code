#Requires -Version 7.2

<#
.SYNOPSIS
    The content that depends on one classic table, directly and through parsers.

.DESCRIPTION
    Direct dependents name the table in their own KQL; with an alias index,
    the content that reaches it only through parsers is added in parallel
    Indirect lists.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/ClassicToDcr/Get-iSOCTableImpactAnalysis.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.0
    Last Updated: 2026-11-04
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCTableImpactAnalysis {
    <#
    .SYNOPSIS
        The content that depends on one classic table, directly and through
        parsers.

    .DESCRIPTION
        A direct dependent names the table in its own KQL
        (Test-iSOCKqlTableReference): an analytics rule's query, a hunting
        query's, a parser's or another saved search's, any query in a
        workbook, anywhere in a Logic App's definition, or a data collection
        rule's transform other than source. With -AliasIndex the content
        that reaches the table only through parser functions is added in the
        Indirect lists (Resolve-iSOCIndirectTableImpact).

        TotalImpacted counts the direct dependents only; TotalAffected adds
        the indirect ones.

    .PARAMETER TableName
        The classic table.

    .PARAMETER Content
        The content, from Read-iSOCTableMigrationContent.

    .PARAMETER AliasIndex
        The alias index, from Get-iSOCParserAliasIndex. Without it no
        indirect dependent is looked for.

    .PARAMETER MaxDepth
        The most parser hops followed. Default 10.

    .OUTPUTS
        [pscustomobject] TableName, TotalImpacted, TotalIndirect,
        TotalAffected, a direct and an Indirect list per content type,
        ChainTruncated and UnresolvedBridges.

    .EXAMPLE
        Get-iSOCTableImpactAnalysis -TableName MyApp_CL -Content $content -AliasIndex $index
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $TableName,

        [Parameter(Mandatory)]
        $Content,

        $AliasIndex,

        [int] $MaxDepth = 10
    )

    $read = { param($Object, $Path) Get-iSOCPropertyValue -InputObject $Object -Path $Path }
    $result = [ordered]@{
        TableName      = $TableName
        AnalyticsRules = @()
        HuntingQueries = @()
        Parsers        = @()
        SavedSearches  = @()
        Workbooks      = @()
        Playbooks      = @()
        Dcrs           = @()
    }

    foreach ($rule in $Content.AlertRules) {
        if (Test-iSOCKqlTableReference -Query (& $read $rule 'properties.query') -TableName $TableName) {
            $result.AnalyticsRules += [pscustomobject]@{
                Name           = ((& $read $rule 'properties.displayName') ?? (& $read $rule 'name'))
                Enabled        = (& $read $rule 'properties.enabled')
                Severity       = (& $read $rule 'properties.severity')
                ResourceId     = (& $read $rule 'id')
                DependencyKind = 'Direct'
            }
        }
    }

    foreach ($hq in $Content.HuntingQueries) {
        if (Test-iSOCKqlTableReference -Query (& $read $hq 'properties.query') -TableName $TableName) {
            $result.HuntingQueries += [pscustomobject]@{
                Name           = ((& $read $hq 'properties.displayName') ?? (& $read $hq 'name'))
                Category       = (& $read $hq 'properties.category')
                ResourceId     = (& $read $hq 'id')
                DependencyKind = 'Direct'
            }
        }
    }

    foreach ($parser in $Content.Parsers) {
        if (Test-iSOCKqlTableReference -Query (& $read $parser 'properties.query') -TableName $TableName) {
            $result.Parsers += [pscustomobject]@{
                Name           = ((& $read $parser 'properties.functionAlias') ?? (& $read $parser 'properties.displayName') ?? (& $read $parser 'name'))
                FunctionAlias  = (& $read $parser 'properties.functionAlias')
                ResourceId     = (& $read $parser 'id')
                DependencyKind = 'Direct'
            }
        }
    }

    foreach ($ss in $Content.SavedSearches) {
        if ((& $read $ss 'properties.category') -eq 'Hunting Queries' -or (& $read $ss 'properties.functionAlias')) { continue }
        if (Test-iSOCKqlTableReference -Query (& $read $ss 'properties.query') -TableName $TableName) {
            $result.SavedSearches += [pscustomobject]@{
                Name           = ((& $read $ss 'properties.displayName') ?? (& $read $ss 'name'))
                Category       = (& $read $ss 'properties.category')
                ResourceId     = (& $read $ss 'id')
                DependencyKind = 'Direct'
            }
        }
    }

    foreach ($wb in $Content.Workbooks) {
        $queries = Get-iSOCWorkbookQueryText -SerializedData (& $read $wb 'properties.serializedData')
        $hits = $queries | Where-Object { Test-iSOCKqlTableReference -Query $_ -TableName $TableName }
        if ($hits) {
            $result.Workbooks += [pscustomobject]@{
                Name           = ((& $read $wb 'properties.displayName') ?? (& $read $wb 'name'))
                QueryCount     = @($hits).Count
                ResourceId     = (& $read $wb 'id')
                DependencyKind = 'Direct'
            }
        }
    }

    foreach ($pb in $Content.Playbooks) {
        $definition = & $read $pb 'properties.definition'
        $defJson = $definition | ConvertTo-Json -Depth 100 -Compress -WarningAction SilentlyContinue
        if ($defJson -and $defJson -match "(?i)(?<![a-zA-Z0-9_])$([regex]::Escape($TableName))(?![a-zA-Z0-9_])") {
            $result.Playbooks += [pscustomobject]@{
                Name           = (& $read $pb 'name')
                State          = (& $read $pb 'properties.state')
                ResourceId     = (& $read $pb 'id')
                DependencyKind = 'Direct'
            }
        }
    }

    foreach ($dcr in $Content.Dcrs) {
        $flows = & $read $dcr 'properties.dataFlows'
        if (-not $flows) { continue }
        $matchedFlowCount = 0
        foreach ($flow in $flows) {
            $transform = & $read $flow 'transformKql'
            if (-not $transform -or $transform -eq 'source') { continue }
            if (Test-iSOCKqlTableReference -Query $transform -TableName $TableName) { $matchedFlowCount++ }
        }
        if ($matchedFlowCount -gt 0) {
            $result.Dcrs += [pscustomobject]@{
                Name           = (& $read $dcr 'name')
                FlowCount      = $matchedFlowCount
                ResourceId     = (& $read $dcr 'id')
                DependencyKind = 'Direct'
            }
        }
    }

    $totalImpacted = $result.AnalyticsRules.Count + $result.HuntingQueries.Count +
    $result.Parsers.Count + $result.SavedSearches.Count +
    $result.Workbooks.Count + $result.Playbooks.Count + $result.Dcrs.Count

    $final = [ordered]@{
        TableName              = $TableName
        TotalImpacted          = $totalImpacted
        TotalIndirect          = 0
        TotalAffected          = $totalImpacted
        AnalyticsRules         = $result.AnalyticsRules
        HuntingQueries         = $result.HuntingQueries
        Parsers                = $result.Parsers
        SavedSearches          = $result.SavedSearches
        Workbooks              = $result.Workbooks
        Playbooks              = $result.Playbooks
        Dcrs                   = $result.Dcrs
        IndirectAnalyticsRules = @()
        IndirectHuntingQueries = @()
        IndirectParsers        = @()
        IndirectSavedSearches  = @()
        IndirectWorkbooks      = @()
        IndirectPlaybooks      = @()
        IndirectDcrs           = @()
        ChainTruncated         = $false
        UnresolvedBridges      = @()
    }

    if ($AliasIndex) {
        $indirect = Resolve-iSOCIndirectTableImpact -TableName $TableName -Index $AliasIndex `
            -DirectImpact ([pscustomobject]$result) -MaxDepth $MaxDepth
        foreach ($type in 'AnalyticsRules', 'HuntingQueries', 'Parsers', 'SavedSearches', 'Workbooks', 'Playbooks', 'Dcrs') {
            $final["Indirect$type"] = @($indirect."Indirect$type")
        }
        $final['TotalIndirect'] = $indirect.TotalIndirect
        $final['TotalAffected'] = $totalImpacted + $indirect.TotalIndirect
        $final['ChainTruncated'] = $indirect.ChainTruncated
        $final['UnresolvedBridges'] = @($indirect.UnresolvedBridges)
    }

    [pscustomobject]$final
}

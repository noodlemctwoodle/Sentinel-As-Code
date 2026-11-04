#Requires -Version 7.2

<#
.SYNOPSIS
    Index which content calls which parser alias, for the parser chains.

.DESCRIPTION
    One pass over the workspace content: the aliases that can be followed,
    those that cannot and why, one node per item, and which nodes call and
    which define each alias.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/ClassicToDcr/Get-iSOCParserAliasIndex.ps1
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

function Get-iSOCParserAliasIndex {
    <#
    .SYNOPSIS
        Index which content calls which parser alias, for the parser chains.

    .DESCRIPTION
        One pass over the content gives:

          Aliases         the aliases that can be followed, ordinal-sorted
          SkippedAliases  those that cannot, with the reason and the
                          content that names them, to be checked by hand
          Nodes           one per content item, in the order ARM listed them
          References      alias to the ids of the nodes that name it
          ProviderIds     alias to the ids of the nodes that define it
          Warnings        aliases named by a large share of all content

        Names are compared ordinally: KQL names are case-sensitive, so
        MyParser and myparser are two functions. Data collection rules are
        left out: an ingestion-time transform runs before the data reaches
        the workspace and cannot call a workspace function. Each node's
        names come from Get-iSOCKqlReferenceIdentifierSet, and a playbook's
        from Get-iSOCPlaybookKqlText only.

        An alias is reported as named by a large share when at least
        -FanoutMinimumHits items name it and they are more than
        -FanoutWarnRatio of the larger of the item count and
        -FanoutMinimumScale. It is still followed.

    .PARAMETER Content
        The content, from Read-iSOCTableMigrationContent.

    .PARAMETER MinimumAliasLength
        The shortest alias followed. Default 4.

    .PARAMETER WorkspaceTableName
        Every table in the workspace.

    .PARAMETER WorkspaceColumnName
        Every column in the workspace.

    .PARAMETER FanoutMinimumHits
        The fewest items that make a warning. Default 20.

    .PARAMETER FanoutMinimumScale
        The smallest item count the share is taken of. Default 50.

    .PARAMETER FanoutWarnRatio
        The share above which an alias is reported. Default 0.30.

    .OUTPUTS
        [pscustomobject] Aliases, SkippedAliases, Nodes, References,
        ProviderIds and Warnings.

    .EXAMPLE
        $index = Get-iSOCParserAliasIndex -Content $content -WorkspaceTableName $inventory.AllTableNames
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        $Content,

        [int] $MinimumAliasLength = 4,

        [AllowNull()]
        [string[]] $WorkspaceTableName,

        [AllowNull()]
        [string[]] $WorkspaceColumnName,

        [int] $FanoutMinimumHits = 20,

        [int] $FanoutMinimumScale = 50,

        [double] $FanoutWarnRatio = 0.30
    )

    $read = { param($Object, $Path) Get-iSOCPropertyValue -InputObject $Object -Path $Path }
    $cmp = [System.StringComparer]::Ordinal

    $safe = [System.Collections.Generic.HashSet[string]]::new($cmp)
    $seenSkip = [System.Collections.Generic.HashSet[string]]::new($cmp)
    $skipInfo = [System.Collections.Generic.List[object]]::new()
    $verdictOf = [System.Collections.Generic.Dictionary[string, object]]::new($cmp)

    foreach ($parser in @($Content.Parsers)) {
        $rawAlias = & $read $parser 'properties.functionAlias'
        $verdict = Get-iSOCFunctionAliasSafety -Alias $rawAlias -MinimumLength $MinimumAliasLength `
            -WorkspaceTableName $WorkspaceTableName -WorkspaceColumnName $WorkspaceColumnName
        if ($verdict.Alias) { $verdictOf[$verdict.Alias] = $verdict }
        if ($verdict.IsSafe) {
            [void]$safe.Add($verdict.Alias)
        }
        elseif ($verdict.Alias -and $seenSkip.Add($verdict.Alias)) {
            $skipInfo.Add([pscustomobject]@{
                    Alias  = $verdict.Alias
                    Parser = ((& $read $parser 'properties.displayName') ?? (& $read $parser 'name'))
                    Reason = $verdict.Reason
                })
        }
    }

    $vocabulary = [string[]]@($safe)
    if ($vocabulary.Count -gt 1) { [array]::Sort($vocabulary, [System.StringComparer]::Ordinal) }

    $skippedTerms = [string[]]@($skipInfo | ForEach-Object { $_.Alias })
    if ($skippedTerms.Count -gt 1) { [array]::Sort($skippedTerms, [System.StringComparer]::Ordinal) }

    $allTerms = [System.Collections.Generic.HashSet[string]]::new($cmp)
    foreach ($term in $vocabulary) { [void]$allTerms.Add($term) }
    foreach ($term in $skippedTerms) { [void]$allTerms.Add($term) }

    $raw = [System.Collections.Generic.List[object]]::new()
    foreach ($rule in @($Content.AlertRules)) {
        $raw.Add([pscustomobject]@{
                Type = 'AnalyticsRules'; Name = ((& $read $rule 'properties.displayName') ?? (& $read $rule 'name'))
                ResourceId = (& $read $rule 'id'); Alias = $null; Parts = @([string](& $read $rule 'properties.query'))
                Enabled = (& $read $rule 'properties.enabled'); Severity = (& $read $rule 'properties.severity')
                Category = $null; State = $null
            })
    }
    foreach ($hq in @($Content.HuntingQueries)) {
        $raw.Add([pscustomobject]@{
                Type = 'HuntingQueries'; Name = ((& $read $hq 'properties.displayName') ?? (& $read $hq 'name'))
                ResourceId = (& $read $hq 'id'); Alias = (& $read $hq 'properties.functionAlias')
                Parts = @([string](& $read $hq 'properties.query'))
                Enabled = $null; Severity = $null; Category = (& $read $hq 'properties.category'); State = $null
            })
    }
    foreach ($parser in @($Content.Parsers)) {
        $raw.Add([pscustomobject]@{
                Type = 'Parsers'
                Name = ((& $read $parser 'properties.functionAlias') ?? (& $read $parser 'properties.displayName') ?? (& $read $parser 'name'))
                ResourceId = (& $read $parser 'id'); Alias = (& $read $parser 'properties.functionAlias')
                Parts = @([string](& $read $parser 'properties.query'))
                Enabled = $null; Severity = $null; Category = $null; State = $null
            })
    }
    foreach ($ss in @($Content.SavedSearches)) {
        if ((& $read $ss 'properties.category') -eq 'Hunting Queries' -or (& $read $ss 'properties.functionAlias')) { continue }
        $raw.Add([pscustomobject]@{
                Type = 'SavedSearches'; Name = ((& $read $ss 'properties.displayName') ?? (& $read $ss 'name'))
                ResourceId = (& $read $ss 'id'); Alias = $null; Parts = @([string](& $read $ss 'properties.query'))
                Enabled = $null; Severity = $null; Category = (& $read $ss 'properties.category'); State = $null
            })
    }
    foreach ($wb in @($Content.Workbooks)) {
        $raw.Add([pscustomobject]@{
                Type = 'Workbooks'; Name = ((& $read $wb 'properties.displayName') ?? (& $read $wb 'name'))
                ResourceId = (& $read $wb 'id'); Alias = $null
                Parts = @(Get-iSOCWorkbookQueryText -SerializedData (& $read $wb 'properties.serializedData'))
                Enabled = $null; Severity = $null; Category = $null; State = $null
            })
    }
    foreach ($pb in @($Content.Playbooks)) {
        $raw.Add([pscustomobject]@{
                Type = 'Playbooks'; Name = (& $read $pb 'name'); ResourceId = (& $read $pb 'id'); Alias = $null
                Parts = @(Get-iSOCPlaybookKqlText -Definition (& $read $pb 'properties.definition'))
                Enabled = $null; Severity = $null; Category = $null; State = (& $read $pb 'properties.state')
            })
    }

    $refs = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[int]]]::new($cmp)
    $skippedRefs = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[int]]]::new($cmp)
    $providers = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.HashSet[int]]]::new($cmp)
    foreach ($term in $vocabulary) { $refs[$term] = [System.Collections.Generic.List[int]]::new() }
    foreach ($term in $skippedTerms) { $skippedRefs[$term] = [System.Collections.Generic.List[int]]::new() }

    $nodes = [System.Collections.Generic.List[object]]::new()
    for ($id = 0; $id -lt $raw.Count; $id++) {
        $n = $raw[$id]
        $counts = [System.Collections.Generic.Dictionary[string, int]]::new($cmp)

        foreach ($part in @($n.Parts)) {
            if ([string]::IsNullOrEmpty($part)) { continue }
            $tokens = Get-iSOCKqlReferenceIdentifierSet -Text @($part)
            foreach ($token in $tokens) {
                if (-not $allTerms.Contains($token)) { continue }
                if ($counts.ContainsKey($token)) { $counts[$token] = $counts[$token] + 1 }
                else { $counts[$token] = 1 }
            }
        }
        foreach ($term in $counts.Keys) {
            if ($refs.ContainsKey($term)) { $refs[$term].Add($id) }
            elseif ($skippedRefs.ContainsKey($term)) { $skippedRefs[$term].Add($id) }
        }

        $nodeAlias = $null
        $trimmedAlias = if ($n.Alias) { ([string]$n.Alias).Trim() } else { $null }
        if ($n.Alias) {
            $aliasVerdict = if ($trimmedAlias -and $verdictOf.ContainsKey($trimmedAlias)) {
                $verdictOf[$trimmedAlias]
            }
            else {
                Get-iSOCFunctionAliasSafety -Alias ([string]$n.Alias) -MinimumLength $MinimumAliasLength `
                    -WorkspaceTableName $WorkspaceTableName -WorkspaceColumnName $WorkspaceColumnName
            }
            if ($aliasVerdict.IsSafe) {
                $nodeAlias = $aliasVerdict.Alias
                if (-not $providers.ContainsKey($nodeAlias)) {
                    $providers[$nodeAlias] = [System.Collections.Generic.HashSet[int]]::new()
                }
                [void]$providers[$nodeAlias].Add($id)
            }
        }

        $nodes.Add([pscustomobject]@{
                Id = $id; Type = $n.Type; Name = $n.Name; ResourceId = $n.ResourceId
                Alias = $nodeAlias; RawAlias = $trimmedAlias
                Enabled = $n.Enabled; Severity = $n.Severity
                Category = $n.Category; State = $n.State; MatchCounts = $counts
            })
    }

    $skipped = [System.Collections.Generic.List[object]]::new()
    foreach ($s in $skipInfo) {
        $ids = if ($skippedRefs.ContainsKey($s.Alias)) { $skippedRefs[$s.Alias] } else { @() }
        $dependents = foreach ($id in $ids) {
            $node = $nodes[$id]
            if ($node.RawAlias -and [string]::Equals($node.RawAlias, $s.Alias, [System.StringComparison]::Ordinal)) { continue }
            [pscustomobject]@{ Type = $node.Type; Name = $node.Name; ResourceId = $node.ResourceId }
        }
        $skipped.Add([pscustomobject]@{
                Alias          = $s.Alias
                Parser         = $s.Parser
                Reason         = $s.Reason
                ReferenceCount = @($dependents).Count
                Dependents     = @($dependents)
            })
    }

    $warnings = [System.Collections.Generic.List[string]]::new()
    if ($nodes.Count -gt 0) {
        $scale = [Math]::Max($nodes.Count, $FanoutMinimumScale)
        foreach ($term in $vocabulary) {
            $hitCount = $refs[$term].Count
            if ($hitCount -ge $FanoutMinimumHits -and (($hitCount / $scale) -gt $FanoutWarnRatio)) {
                $pct = [Math]::Round((($hitCount / $nodes.Count) * 100))
                $warnings.Add("Parser alias '$term' is referenced by $hitCount of $($nodes.Count) content items ($pct%) - treat the chains it produces as suspect")
            }
        }
    }

    [pscustomobject]@{
        Aliases        = @($vocabulary)
        SkippedAliases = @($skipped)
        Nodes          = @($nodes)
        References     = $refs
        ProviderIds    = $providers
        Warnings       = @($warnings)
    }
}

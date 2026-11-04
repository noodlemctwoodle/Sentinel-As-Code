#Requires -Version 7.2

<#
.SYNOPSIS
    Log what the impact analysis found: the totals, the chained dependents and where the chains stop.

.DESCRIPTION
    The totals, the tables a search for their name would under-report, the
    chains deeper than the limit, and the parsers whose callers cannot be
    listed.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/ClassicToDcr/Write-iSOCTableMigrationFinding.ps1
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

function Write-iSOCTableMigrationFinding {
    <#
    .SYNOPSIS
        Log what the impact analysis found: the totals, the chained
        dependents and where the chains stop.

    .DESCRIPTION
        The dependents across the tables, direct and through parsers; the
        tables with dependents that a search for the table name would not
        find, and the parsers that bridge them; the tables whose chains go
        deeper than -MaxParserChainDepth; and the parsers that read a table
        but whose alias cannot be followed, with the content that names that
        alias, which has to be checked by hand.

    .PARAMETER Impacts
        The impact of each table.

    .PARAMETER TableCount
        How many classic tables were scanned.

    .PARAMETER MaxParserChainDepth
        The chain limit the analysis used.

    .EXAMPLE
        Write-iSOCTableMigrationFinding -Impacts $impacts -TableCount $tables.Count -MaxParserChainDepth 10
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [object[]] $Impacts,

        [int] $TableCount,

        [int] $MaxParserChainDepth
    )

    $types = 'AnalyticsRules', 'HuntingQueries', 'Parsers', 'SavedSearches', 'Workbooks', 'Playbooks', 'Dcrs'
    $directTotal = [int](($Impacts | Measure-Object -Property TotalImpacted -Sum).Sum)
    $indirectTotal = [int](($Impacts | Measure-Object -Property TotalIndirect -Sum).Sum)
    $affectedTables = @($Impacts | Where-Object { ($_.TotalImpacted + $_.TotalIndirect) -gt 0 }).Count

    Write-iSOCLog ("Scan complete - $($directTotal + $indirectTotal) dependent items across " +
        "$affectedTables of $TableCount tables ($directTotal direct, $indirectTotal via parsers)") -Level Success

    if ($indirectTotal -gt 0) {
        $bridges = @($Impacts | ForEach-Object {
                $impact = $_
                foreach ($type in $types) {
                    foreach ($item in $impact."Indirect$type") { $item.Via }
                }
            } | Sort-Object -Unique)
        Write-iSOCLog ("$indirectTotal item(s) reach a classic table only through a parser function " +
            "($($bridges.Count) parser(s) act as the bridge). They never name the table, and they break on migration.") -Level Warning

        $chained = @($Impacts | Where-Object { $_.TotalIndirect -gt 0 })
        Write-iSOCLog "$($chained.Count) table(s) have dependents that a search for the table name would not find:" -Level Warning
        foreach ($c in $chained) {
            Write-iSOCLog "    - $($c.TableName) - $($c.TotalImpacted) direct, $($c.TotalIndirect) via parser"
        }
    }

    $truncated = @($Impacts | Where-Object { $_.ChainTruncated })
    if ($truncated.Count -gt 0) {
        Write-iSOCLog ("Dependency chains for $($truncated.Count) table(s) are deeper than $MaxParserChainDepth parser hops - " +
            'anything past that depth is not listed. Re-run with a higher -MaxParserChainDepth.') -Level Warning
    }

    $bridged = @($Impacts | Where-Object { @($_.UnresolvedBridges).Count -gt 0 })
    if ($bridged.Count -gt 0) {
        Write-iSOCLog ("$($bridged.Count) table(s) reach a parser whose alias could not be resolved. " +
            'Content calling those parsers is NOT listed and needs checking by hand:') -Level Warning
        foreach ($b in $bridged) {
            foreach ($u in @($b.UnresolvedBridges)) {
                Write-iSOCLog "    - $($b.TableName) -> parser '$($u.Parser)' (alias '$($u.Alias)') - $($u.Reason)"
                if ($u.ReferenceCount -gt 0) {
                    Write-iSOCLog "        $($u.ReferenceCount) item(s) name that alias and were not resolved:"
                    foreach ($d in @($u.Dependents)) {
                        Write-iSOCLog "          - [$($d.Type)] $($d.Name)"
                    }
                }
            }
        }
    }
}

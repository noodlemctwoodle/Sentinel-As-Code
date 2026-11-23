#Requires -Version 7.6

<#
.SYNOPSIS
    Build the figures for and write 30-hunting-queries.md.

.DESCRIPTION
    A step of the Blueprint renderer. Steps run in order and pass their results
    to later ones through the render context, so this one may also prepare
    figures that a later page uses.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/HuntingQueries/Write-BlueprintHuntingQueriesSection.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.
function Write-BlueprintHuntingQueriesSection {
    <#
    .SYNOPSIS
        Build the figures for and write 30-hunting-queries.md.

    .PARAMETER Context
        The render context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the render context.
    $bookmarkCountDoc = $Context.bookmarkCountDoc
    $bookmarks = $Context.bookmarks
    $bookmarksFromLogs = $Context.bookmarksFromLogs
    $hunts = $Context.hunts
    $key = $Context.key
    $m = $Context.m
    $n = $Context.n
    $p = $Context.p
    $rawRoot = $Context.rawRoot
    $workspaceTables = $Context.workspaceTables

    # ---------------------------------------------------------------------------
    # Section: 30 / 35 — hunting & parsers
    # ---------------------------------------------------------------------------
    $hunting = Read-BlueprintRawArray 'hunting-queries.json'
    $parsers = Read-BlueprintRawArray 'parsers-functions.json'

    $huntingRows = $hunting | ForEach-Object {
        [pscustomobject]@{
            Name = $_.properties.displayName
            Tags = ($_.properties.tags | ForEach-Object { "$($_.name)=$($_.value)" }) -join ', '
        }
    }
    # Aggregate hunting queries by tactic (parsed from the tactics= tag value).
    $huntByTactic = @{}
    foreach ($h in $hunting) {
        # Named so it cannot shadow $tactics, the MITRE catalogue that the
        # section-01 headline counts.
        $huntTacticTags = @($h.properties.tags | Where-Object { $_.name -eq 'tactics' } | ForEach-Object { $_.value })
        if (-not $huntTacticTags) { $huntTacticTags = @('Untagged') }
        foreach ($t in $huntTacticTags) {
            # tactics tag can be a comma-separated list
            foreach ($tac in ($t -split ',')) {
                $key = $(if ($tac.Trim()) { Format-TacticName $tac } else { '' })
                if (-not $key) { continue }
                if (-not $huntByTactic.ContainsKey($key)) { $huntByTactic[$key] = 0 }
                $huntByTactic[$key]++
            }
        }
    }
    $huntPieRows = Format-PieSlice -Counts $huntByTactic
    $huntChartBlock = if ($hunting.Count -gt 0 -and $huntPieRows.Count -gt 0) {
        @"

## Hunting queries by tactic

``````mermaid
pie showData title Hunting queries by MITRE tactic
$($huntPieRows -join [Environment]::NewLine)
``````

$(Format-BlueprintPlural $hunting.Count 'hunting query' 'hunting queries'). Tactic distribution reveals where the SOC's free-form investigation library is strongest and where the gaps live.
"@
    } else { '' }

    # When the bookmarks API refused its list as too large, the collector lists
    # them from the HuntingBookmark table instead.
    $bookmarksListed = @($bookmarks | Where-Object { $_ })
    $bookmarksFromTable = $false
    if ($bookmarksListed.Count -eq 0 -and @($bookmarksFromLogs | Where-Object { $_ }).Count -gt 0) {
        $bookmarksListed = @($bookmarksFromLogs | Where-Object { $_ })
        $bookmarksFromTable = $true
    }
    $bookmarkServiceCount = if ($bookmarkCountDoc) { [int](ConvertTo-BlueprintNumber (Get-BlueprintRawProperty $bookmarkCountDoc 'Count' 0)) } else { 0 }
    $bookmarkRows = @($bookmarksListed | ForEach-Object {
            $p = Get-BlueprintRawProperty $_ 'properties' $null
            $created = [string](Get-BlueprintRawProperty $p 'created' '')
            [pscustomobject]@{
                Name      = [string](Get-BlueprintRawProperty $p 'displayName' (Get-BlueprintRawProperty $_ 'name' ''))
                Created   = $(if ($created) { try { Format-DateUtc $created } catch { $created } } else { '' })
                CreatedAt = $(if ($created) { try { ([datetime]$created).ToUniversalTime() } catch { [datetime]::MinValue } } else { [datetime]::MinValue })
                Labels    = (@(Get-BlueprintRawProperty $p 'labels' @()) -join ', ')
                Notes     = [string](Get-BlueprintRawProperty $p 'notes' '')
            }
        })
    $bookmarkBlock = if ($bookmarkRows.Count -gt 0) {
        $bookmarkIntro = if ($bookmarksFromTable) {
            $refused = if ($bookmarkServiceCount -gt 0) { "The bookmarks API refused its list of **$(Format-BlueprintPlural $bookmarkServiceCount 'bookmark')** as too large" } else { 'The bookmarks API refused its list as too large' }
            $held = if ($bookmarkServiceCount -gt $bookmarkRows.Count) { " The table holds $(Format-BlueprintCount $bookmarkRows.Count) of the $(Format-BlueprintCount $bookmarkServiceCount): it keeps entries only for its retention period, so a bookmark not changed within that period is not in it." } else { '' }
            "$refused, so these $(Format-BlueprintCount $bookmarkRows.Count) come from the HuntingBookmark table, where Microsoft Sentinel logs every bookmark, newest first.$held Their labels are the analyst's own tags."
        } else {
            "Bookmarks saved from hunting and investigation, newest first. Their labels are the analyst's own tags."
        }
        "$bookmarkIntro`n`n" + (Format-BlueprintTable -Items @($bookmarkRows | Sort-Object CreatedAt -Descending) -Columns 'Name', 'Created', 'Labels', 'Notes')
    } elseif ($bookmarkServiceCount -gt 0) {
        # bookmarks-from-logs.json present but empty: the table was read and
        # holds none of them; absent: the table could not be read.
        if (Test-Path -LiteralPath (Join-Path $rawRoot 'bookmarks-from-logs.json')) {
            # The table logs every bookmark change, so holding none means no
            # bookmark was created, changed or deleted within its retention.
            $hbTable = @($workspaceTables | Where-Object { $_ -and [string](Get-BlueprintRawProperty $_ 'name' '') -eq 'HuntingBookmark' }) | Select-Object -First 1
            $hbDays = if ($hbTable) { [int](ConvertTo-BlueprintNumber (Get-BlueprintRawProperty (Get-BlueprintRawProperty $hbTable 'properties' $null) 'retentionInDays' 0)) } else { 0 }
            if ($hbDays -gt 0) {
                "**$(Format-BlueprintCount $bookmarkServiceCount) bookmarks** exist, and none has been created, changed or deleted in the last $(Format-BlueprintPlural $hbDays 'day'): the HuntingBookmark table, which logs every bookmark change and keeps $(Format-BlueprintPlural $hbDays 'day'), holds no entries. The bookmarks API refused its list as too large, so only the count was captured."
            } else {
                "**$(Format-BlueprintCount $bookmarkServiceCount) bookmarks** exist. The list was too large for the API to return, and the HuntingBookmark table, which keeps entries only for its retention period, holds none of them, so only the count was captured."
            }
        } else {
            "**$(Format-BlueprintCount $bookmarkServiceCount) bookmarks** exist. The list was too large for the API to return and the HuntingBookmark table could not be read, so only the count was captured."
        }
    } else { '_None._' }
    $huntRows = @($hunts | ForEach-Object {
            $p = if ($_.PSObject.Properties['properties'] -and $_.properties) { $_.properties } else { $_ }
            $owner = ''
            if ($p.PSObject.Properties['owner'] -and $p.owner) {
                if ($p.owner.PSObject.Properties['assignedTo'] -and $p.owner.assignedTo) { $owner = $p.owner.assignedTo }
                elseif ($p.owner.PSObject.Properties['email'] -and $p.owner.email) { $owner = $p.owner.email }
            }
            [pscustomobject]@{
                Name       = if ($p.PSObject.Properties['displayName']) { $p.displayName } elseif ($_.PSObject.Properties['name']) { $_.name } else { '' }
                Status     = if ($p.PSObject.Properties['status']) { $p.status } else { '' }
                Hypothesis = if ($p.PSObject.Properties['hypothesisStatus']) { $p.hypothesisStatus } else { '' }
                Tactics    = if ($p.PSObject.Properties['attackTactics']) { Format-TacticList $p.attackTactics } else { '' }
                Owner      = $owner
            }
        })

    Write-BlueprintSection '30-hunting-queries.md' (@"
$(Format-Banner -Title 'Hunting Queries')
$huntChartBlock

$(Format-BlueprintTable -Items $huntingRows -Columns 'Name','Tags')

## Hunts

Hunts recorded through the Hunts feature, with their hypothesis status. Bookmarks promoted from a hunt show on the incidents they were attached to. [SAC-HNT-01] fires when there are no hunts and no bookmarks at all.

$(Format-BlueprintTable -Items $huntRows -Columns 'Name','Status','Hypothesis','Tactics','Owner')

## Bookmarks

$bookmarkBlock

[Hunts in Microsoft Sentinel (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/hunts)
"@)

    # Left in the render context for later sections.
    if (Get-Variable -Name 'key' -Scope 0 -ErrorAction Ignore) { $Context.key = $key }
    $Context.parsers = $parsers
    $Context.t = $t
}

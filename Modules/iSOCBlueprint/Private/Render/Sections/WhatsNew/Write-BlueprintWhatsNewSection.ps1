#Requires -Version 7.6

<#
.SYNOPSIS
    Build the figures for and write 03-whats-new.md.

.DESCRIPTION
    A step of the Blueprint renderer. Steps run in order and pass their results
    to later ones through the render context, so this one may also prepare
    figures that a later page uses.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/WhatsNew/Write-BlueprintWhatsNewSection.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.2
    Last Updated: 2026-11-16
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.
function Write-BlueprintWhatsNewSection {
    <#
    .SYNOPSIS
        Build the figures for and write 03-whats-new.md.

    .PARAMETER Context
        The render context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the render context.
    $d = $Context.d
    $m = $Context.m
    $maturity = $Context.maturity
    $maturityOk = $Context.maturityOk
    $n = $Context.n
    $p = $Context.p
    $ResourcesRoot = $Context.ResourcesRoot
    $s = $Context.s
    $t = $Context.t

    # Section 03: what Microsoft has released, previewed and announced for
    # retirement in Sentinel and Defender XDR, from their What's new pages on
    # Microsoft Learn (the collector's whats-new.json), each item linked to the
    # report pages and maturity criteria it touches with this workspace's status.
    $whatsNew = Read-BlueprintRaw 'whats-new.json'
    $wnItems = @(if ($whatsNew -and $whatsNew.PSObject.Properties['Items']) { @($whatsNew.Items | Where-Object { $_ }) })
    $wnTopicsPath = Join-Path $ResourcesRoot 'whats-new-topics.json'
    $wnTopics = @(if (Test-Path -LiteralPath $wnTopicsPath) { @((Get-Content -LiteralPath $wnTopicsPath -Raw | ConvertFrom-Json).topics) })
    $wnCriterion = @{}
    if ($maturityOk) { foreach ($a in @($maturity.areas)) { foreach ($c in @($a.criteria)) { if ($c -and $c.id) { $wnCriterion[[string]$c.id] = $c } } } }
    # An item's first sentence: the table stays readable, and the item links to
    # its full entry on Learn.
    $wnFirstSentence = { param([string]$T)
        $m = [regex]::Match($T, '^(.{40,}?[.!?])(\s|$)')
        $s = if ($m.Success) { $m.Groups[1].Value } else { $T }
        if ($s.Length -gt 240) { $cut = $s.LastIndexOf(' ', 240); $s = $s.Substring(0, $(if ($cut -gt 0) { $cut } else { 240 })) + [char]0x2026 }
        $s
    }
    # A deadline that has gone by says so.
    $wnToday = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
    # The deadline reads as a date ("30 Jun 2026", or "Jun 2026" for a month), and
    # a Deadline that has gone by says so. Rows sort on the ISO text in DeadlineKey.
    $wnDeadline = { param([string]$D)
        if (-not $D) { return '' }
        $shown = $D
        $inv = [System.Globalization.CultureInfo]::InvariantCulture
        $parsed = [datetime]::MinValue
        if ($D -match '^\d{4}-\d{2}-\d{2}$' -and [datetime]::TryParseExact($D, 'yyyy-MM-dd', $inv, [System.Globalization.DateTimeStyles]::None, [ref]$parsed)) {
            $shown = $parsed.ToString('d MMM yyyy', $inv)
        } elseif ($D -match '^\d{4}-\d{2}$' -and [datetime]::TryParseExact($D, 'yyyy-MM', $inv, [System.Globalization.DateTimeStyles]::None, [ref]$parsed)) {
            $shown = $parsed.ToString('MMM yyyy', $inv)
        }
        if ($D.Length -le $wnToday.Length -and [string]::CompareOrdinal($D, $wnToday.Substring(0, $D.Length)) -lt 0) { "$shown (passed)" } else { $shown }
    }
    $wnMonth = {
        param([string]$M) try {
            ([datetime]::ParseExact($M, 'yyyy-MM', [System.Globalization.CultureInfo]::InvariantCulture)).ToString('MMM yyyy',
                [System.Globalization.CultureInfo]::InvariantCulture)
        } catch { $M }
    }
    $wnRows = @($wnItems | ForEach-Object {
            $rel = Get-WhatsNewRelation -Item $_
            [pscustomobject]@{
                Product           = [string]$_.Product
                Month             = (& $wnMonth ([string]$_.Month))
                Status            = [string]$_.Status
                Item              = "[$(([string]$_.Title) -replace '\|', '/')]($([string]$_.Link))"
                Summary           = ((& $wnFirstSentence ([string]$_.Summary)) -replace '\|', '/')
                Deadline          = $(if ($_.PSObject.Properties['Deadline'] -and $_.Deadline) { & $wnDeadline ([string]$_.Deadline) } else { '' })
                DeadlineKey       = $(if ($_.PSObject.Properties['Deadline'] -and $_.Deadline) { [string]$_.Deadline } else { '' })
                'Relates to here' = $rel
                Gap               = [bool]($rel -match '\b(gap|unknown)\b')
            }
        })
    $wnStatusOrder = 'Action needed', 'Retiring', 'Generally available', 'Preview', 'Update'
    $wnCount = { param([string]$S, [string]$P) @($wnRows | Where-Object { $_.Status -eq $S -and (-not $P -or $_.Product -eq $P) }).Count }
    $wnActionRows = @(
        $wnRows |
            Where-Object { $_.Status -in 'Action needed', 'Retiring' } |
            Sort-Object @{ Expression = { if ($_.DeadlineKey) { $_.DeadlineKey } else { '9999' } } }
    )
    $wnGapCount = @($wnRows | Where-Object Gap).Count
    $wnTone = @{ 'Action needed' = 'warn'; 'Retiring' = 'bad'; 'Generally available' = 'ok'; 'Preview' = 'info'; 'Update' = 'neutral' }
    $wnVisualLine = Format-VisualLine -Kind 'meters' -Data ([ordered]@{
            meters  = @(foreach ($p in 'Microsoft Sentinel', 'Microsoft Defender XDR') {
                    [ordered]@{
                        title   = $p
                        caption = "Items in the last $(if ($whatsNew) { $whatsNew.Months } else { 12 }) months"
                        total   = @($wnRows | Where-Object Product -EQ $p).Count
                        parts   = @(foreach ($s in $wnStatusOrder) { [ordered]@{ label = $s; value = (& $wnCount $s $p); tone = $wnTone[$s] } })
                    }
                })
            figures = @(
                [ordered]@{ label = 'Retiring or needing action'; value = $wnActionRows.Count; caption = 'Listed first below, soonest deadline first' }
                [ordered]@{
                    label   = 'Touching a criterion not met here'
                    value   = $wnGapCount
                    caption = 'A linked maturity criterion is a gap or unknown on this workspace'
                }
            )
        })
    $wnSources = @(if ($whatsNew -and $whatsNew.PSObject.Properties['Sources']) { @($whatsNew.Sources) })
    $wnFetched = if ($whatsNew -and $whatsNew.PSObject.Properties['FetchedUtc']) { Format-BlueprintDate $whatsNew.FetchedUtc -Time } else { '' }
    $wnPages = if ($wnSources.Count) { $wnSources } else {
        @([pscustomobject]@{ Product = 'Microsoft Sentinel'; Url = 'https://learn.microsoft.com/en-us/azure/sentinel/whats-new' }
            [pscustomobject]@{ Product = 'Microsoft Defender XDR'; Url = 'https://learn.microsoft.com/en-us/defender-xdr/whats-new' })
    }
    $wnSourceLines = (@($wnPages | ForEach-Object {
                "- [What's new in $($_.Product) (Microsoft Learn)]($($_.Url))$(if ($_.PSObject.Properties['Ok'] -and -not $_.Ok) { ', which could not be read in this run' })"
            }) -join [Environment]::NewLine)
    $wnBody = if (-not $wnItems.Count) {
        @"
$(Format-Banner -Title "What's New")

What Microsoft has released, previewed and announced for retirement in Microsoft Sentinel and Microsoft Defender XDR, read from their What's new pages on Microsoft Learn and linked to this report's pages and maturity criteria.

_Not captured in this snapshot: the collector reads the two What's new pages when it runs, and this inventory has no copy of them (the pages could not be reached, or an older collector took the inventory)._

$wnSourceLines
"@
    } else {
        @"
$(Format-Banner -Title "What's New")

What Microsoft has released, previewed and announced for retirement in Microsoft Sentinel and Microsoft Defender XDR over the last $($whatsNew.Months) months, read from their What's new pages on Microsoft Learn on $wnFetched. Each item links to its entry on Learn and to the pages of this report and the maturity criteria it touches, with this workspace's status for each criterion; a criterion whose finding fired links to the finding.

## At a glance

``````mermaid
pie showData title What's new by status (last $($whatsNew.Months) months)
$wnVisualLine
$(($wnStatusOrder | ForEach-Object { $n = (& $wnCount $_ ''); if ($n -gt 0) { "    `"$_`" : $n" } }) -join [Environment]::NewLine)
``````

<!-- bp:shown-in-graphic -->

**$(Format-BlueprintCount $wnRows.Count)** items  ·  **$(Format-BlueprintCount (& $wnCount 'Generally available' ''))** generally available  ·  **$(Format-BlueprintCount (& $wnCount 'Preview' ''))** in preview  ·  **$(Format-BlueprintCount $wnActionRows.Count)** retiring or needing action  ·  **$(Format-BlueprintCount $wnGapCount)** touching a criterion not met here

## Retiring and action needed

Retirements, deprecations and calls to action, the soonest deadline first. Check each against the pages it links to before the date it names.

$(Format-BlueprintTable -Items $wnActionRows -Columns 'Deadline','Product','Status','Item','Summary','Relates to here' -EmptyMessage '_Nothing retiring or needing action in this window._')

## Microsoft Sentinel

$(Format-BlueprintTable -Items @($wnRows | Where-Object Product -EQ 'Microsoft Sentinel') -Columns 'Month','Status','Item','Summary','Relates to here' -EmptyMessage '_No items in this window._')

## Microsoft Defender XDR

$(Format-BlueprintTable -Items @($wnRows | Where-Object Product -EQ 'Microsoft Defender XDR') -Columns 'Month','Status','Item','Summary','Relates to here' -EmptyMessage '_No items in this window._')

## How each item's status is set

The status comes from each entry's own wording: a call to action is Action needed; retired, retiring, deprecated or transitioning is Retiring; then Generally available or Preview as Microsoft marks it; anything else is Update. The links to this report come from Resources/Data/whats-new-topics.json.

$wnSourceLines
"@
    }
    Write-BlueprintSection '03-whats-new.md' $wnBody

    # Left in the render context for later sections.
    $Context.p = $p
    $Context.s = $s
}

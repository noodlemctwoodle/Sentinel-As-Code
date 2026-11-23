#Requires -Version 7.6

<#
.SYNOPSIS
    Fetch and read both What's new pages, keeping the items of the last Months months.

.DESCRIPTION
    Microsoft Learn returns a page's Markdown when asked for text/markdown,
    so the two What's new pages are read as Markdown rather than scraped.
    The Sentinel page gives each month a "## Month yyyy" heading and each
    item a "### Title"; the Defender XDR page gives each item a top-level
    bullet, "(Preview)" or "(GA)" first and its title in bold, with any
    nested bullets as its detail. Both shapes are read the same way into
    one list of items: product, month, title, status, summary, detail, the
    item's own link on the page, its first Learn link, and for a retirement
    or a call to action the date it names.

    Status is Action needed (a call to action), Retiring (retired,
    deprecated, transitioning, end of support), Generally available,
    Preview, or Update. The collector saves the result as whats-new.json;
    the renderer's What's new page links each item to the report pages and
    maturity criteria it touches.

.NOTES
    File:         Modules/iSOCBlueprint/Private/WhatsNew/Get-WhatsNew.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.1.2
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, What's new reading
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-WhatsNew {
    <#
    .SYNOPSIS
        Fetch and read both What's new pages, keeping the items of the last
        Months months.

    .PARAMETER Months
        How many months back to keep, the current month included. 12 by
        default.

    .PARAMETER Now
        The date to count back from; the current UTC date by default.

    .OUTPUTS
        [pscustomobject] FetchedUtc, Months, Sources (Product, Url, Ok,
        Error, Items), Items (newest month first, then page order).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [ValidateRange(1, 60)] [int] $Months = 12,
        [datetime] $Now = (Get-Date).ToUniversalTime()
    )

    $since = (Get-Date -Year $Now.Year -Month $Now.Month -Day 1).AddMonths(1 - $Months).ToString('yyyy-MM')
    $items = [System.Collections.Generic.List[object]]::new()
    $sources = foreach ($s in $script:WhatsNewSources) {
        try {
            $resp = Invoke-WebRequest -Uri $s.Url -Headers @{ Accept = 'text/markdown' } -TimeoutSec 30 -UseBasicParsing -ErrorAction Stop
            $kept = @(
                ConvertFrom-WhatsNewMarkdown -Markdown ([string]$resp.Content) -Product $s.Product -PageUrl $s.Url |
                    Where-Object { [string]::CompareOrdinal($_.Month, $since) -ge 0 }
            )
            foreach ($k in $kept) { $items.Add($k) }
            [pscustomobject]@{ Product = $s.Product; Url = $s.Url; Ok = $true; Error = $null; Items = $kept.Count }
        } catch {
            [pscustomobject]@{ Product = $s.Product; Url = $s.Url; Ok = $false; Error = $_.Exception.Message; Items = 0 }
        }
    }
    $ordered = @($items | Sort-Object @{ Expression = 'Month'; Descending = $true } -Stable)
    return [pscustomobject]@{
        FetchedUtc = $Now.ToString('o')
        Months     = $Months
        Sources    = @($sources)
        Items      = $ordered
    }
}

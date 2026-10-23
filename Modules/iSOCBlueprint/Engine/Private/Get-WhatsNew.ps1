#Requires -Version 7.2

<#
.SYNOPSIS
    What Microsoft has released, previewed and announced for retirement in
    Microsoft Sentinel and Microsoft Defender XDR, from their What's new
    pages on Microsoft Learn.

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
    File:         Modules/iSOCBlueprint/Engine/Private/Get-WhatsNew.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-14
    Version:      0.1.0
    Last Updated: 2026-10-14
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

$script:WhatsNewSources = @(
    [pscustomobject]@{ Product = 'Microsoft Sentinel'; Url = 'https://learn.microsoft.com/en-us/azure/sentinel/whats-new' }
    [pscustomobject]@{ Product = 'Microsoft Defender XDR'; Url = 'https://learn.microsoft.com/en-us/defender-xdr/whats-new' }
)

function ConvertTo-WhatsNewSlug {
    <#
    .SYNOPSIS
        The anchor Microsoft Learn gives a heading: lower case, anything but
        letters, digits, spaces and hyphens dropped, each space a hyphen.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowEmptyString()] [string] $Text)
    return (($Text.ToLowerInvariant() -replace '[^a-z0-9 \-]', '') -replace ' ', '-')
}

function ConvertTo-WhatsNewPlain {
    <#
    .SYNOPSIS
        Markdown inline text as plain text: links and images to their text,
        emphasis and code marks removed, spaces collapsed.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowEmptyString()] [string] $Text)
    $t = $Text -replace '!\[[^\]]*\]\([^)]*\)', ''
    $t = $t -replace '\[([^\]]*)\]\([^)]*\)', '$1'
    $t = $t -replace '\*\*|__', '' -replace '\*(\S[^*]*?)\*', '$1' -replace '`', ''
    return (($t -replace '\s+', ' ').Trim())
}

function Resolve-WhatsNewLink {
    <#
    .SYNOPSIS
        A link on a Learn page as an absolute URL: site-relative paths on
        learn.microsoft.com, bare paths beside the page.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string] $Href, [string] $PageUrl)
    $h = $Href.Trim()
    if ($h -match '^https?://') { return $h }
    if ($h.StartsWith('/')) { return 'https://learn.microsoft.com' + $h }
    if ($h.StartsWith('#')) { return $PageUrl + $h }
    $base = $PageUrl.Substring(0, $PageUrl.LastIndexOf('/') + 1)
    return $base + $h
}

function Get-WhatsNewStatus {
    <#
    .SYNOPSIS
        Action needed, Retiring, Generally available, Preview or Update.
        A call to action or a retirement outranks a release status, since
        it is what the reader has to act on.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowEmptyString()] [string] $Title, [AllowEmptyString()] [string] $Text, [AllowEmptyString()] [string] $Prefix)
    if ($Title -match '(?i)call to action') { return 'Action needed' }
    if ("$Title $Text" -match '(?i)\bretir(e|ed|es|ing|ement)\b|\bdeprecat|end of support|no longer (be )?(supported|available)|\btransitioning\b|will stop (delivering|working|being)') { return 'Retiring' }
    if ($Prefix -match '(?i)^GA$' -or $Title -match '(?i)generally available|\(GA\)') { return 'Generally available' }
    if ($Prefix -match '(?i)^preview$' -or $Title -match '(?i)\(preview\)|\bpreview\b') { return 'Preview' }
    return 'Update'
}

function Get-WhatsNewDeadline {
    <#
    .SYNOPSIS
        The date a retirement or call to action names, as yyyy-MM-dd, or
        yyyy-MM when it names only a month; the latest when it names more
        than one. $null when it names none.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowEmptyString()] [string] $Text)
    $months = 'January|February|March|April|May|June|July|August|September|October|November|December'
    $found = foreach ($m in [regex]::Matches($Text, "(?i)\b($months)\s+(?:(\d{1,2})(?:st|nd|rd|th)?,?\s+)?(\d{4})\b")) {
        $mon = [datetime]::ParseExact($m.Groups[1].Value, 'MMMM', [System.Globalization.CultureInfo]::InvariantCulture).Month
        $year = [int]$m.Groups[3].Value
        if ($m.Groups[2].Success) {
            $day = [int]$m.Groups[2].Value
            if ($day -ge 1 -and $day -le [datetime]::DaysInMonth($year, $mon)) {
                [pscustomobject]@{ Sort = (Get-Date -Year $year -Month $mon -Day $day).Date; Text = '{0:D4}-{1:D2}-{2:D2}' -f $year, $mon, $day }
            }
        }
        else { [pscustomobject]@{ Sort = (Get-Date -Year $year -Month $mon -Day 1).Date; Text = '{0:D4}-{1:D2}' -f $year, $mon } }
    }
    if (-not $found) { return $null }
    return (@($found) | Sort-Object Sort | Select-Object -Last 1).Text
}

function ConvertFrom-WhatsNewMarkdown {
    <#
    .SYNOPSIS
        The items of one What's new page, from its Markdown.

    .PARAMETER Markdown
        The page as Microsoft Learn returns it for text/markdown.

    .PARAMETER Product
        The product the page covers, carried on every item.

    .PARAMETER PageUrl
        The page's address, for item links and relative Learn links.

    .OUTPUTS
        [pscustomobject] Product, Month (yyyy-MM), Title, Status, Summary,
        Details (string[]), Link, LearnMore, Deadline.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Markdown,
        [Parameter(Mandatory)] [string] $Product,
        [Parameter(Mandatory)] [string] $PageUrl
    )

    $lines = $Markdown -split "\r?\n"
    $i = 0
    # Front matter.
    if ($lines.Count -and $lines[0].Trim() -eq '---') {
        $i = 1
        while ($i -lt $lines.Count -and $lines[$i].Trim() -ne '---') { $i++ }
        $i++
    }
    # Months: the "## Month yyyy" headings, each with its lines.
    $monthsList = [System.Collections.Generic.List[object]]::new()
    $current = $null
    for (; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -match '^##\s+(.+?)\s*$' -and $line -notmatch '^###') {
            $label = $Matches[1].Trim()
            $date = [datetime]::MinValue
            if ([datetime]::TryParseExact($label, 'MMMM yyyy', [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$date)) {
                $current = [pscustomobject]@{ Month = $date.ToString('yyyy-MM'); Label = $label; Lines = [System.Collections.Generic.List[string]]::new() }
                $monthsList.Add($current)
            }
            else { $current = $null }
            continue
        }
        if ($current) { $current.Lines.Add($line) }
    }

    foreach ($month in $monthsList) {
        $body = $month.Lines.ToArray()
        $monthLink = $PageUrl + '#' + (ConvertTo-WhatsNewSlug $month.Label)
        if (@($body | Where-Object { $_ -match '^###\s' }).Count) {
            # Sentinel shape: each ### heading is an item; anything before the
            # first (a month's introduction and its contents list) is not.
            $j = 0
            while ($j -lt $body.Count) {
                if ($body[$j] -notmatch '^###\s+(.+?)\s*$') { $j++; continue }
                $rawTitle = $Matches[1].Trim()
                $j++
                $text = [System.Collections.Generic.List[string]]::new()
                while ($j -lt $body.Count -and $body[$j] -notmatch '^###\s') { $text.Add($body[$j]); $j++ }
                $paras = @(($text -join "`n") -split "\n\s*\n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -notmatch '^(Note|Important|Tip|Caution|Warning)$' -and $_ -notmatch '^[-*|>#]' })
                $summary = if ($paras.Count) { ConvertTo-WhatsNewPlain $paras[0] } else { '' }
                $details = @($text | Where-Object { $_ -match '^\s*[-*]\s+' } | ForEach-Object { ConvertTo-WhatsNewPlain ($_ -replace '^\s*[-*]\s+', '') } | Where-Object { $_ })
                $title = ConvertTo-WhatsNewPlain $rawTitle
                $all = ($text -join ' ')
                $firstLink = [regex]::Match($all, '\]\(([^)\s]+)\)')
                $status = Get-WhatsNewStatus -Title $title -Text $summary -Prefix ''
                [pscustomobject]@{
                    Product   = $Product
                    Month     = $month.Month
                    Title     = $title
                    Status    = $status
                    Summary   = $summary
                    Details   = $details
                    Link      = $PageUrl + '#' + (ConvertTo-WhatsNewSlug $rawTitle)
                    LearnMore = $(if ($firstLink.Success) { Resolve-WhatsNewLink -Href $firstLink.Groups[1].Value -PageUrl $PageUrl } else { $null })
                    Deadline  = $(if ($status -in 'Retiring', 'Action needed') { Get-WhatsNewDeadline -Text "$title $summary" } else { $null })
                }
            }
        }
        else {
            # Defender XDR shape: each top-level bullet is an item, its nested
            # bullets its detail.
            $j = 0
            while ($j -lt $body.Count) {
                if ($body[$j] -notmatch '^[-*]\s+(.+)$') { $j++; continue }
                $first = $Matches[1].Trim()
                $j++
                $cont = [System.Collections.Generic.List[string]]::new()
                $details = [System.Collections.Generic.List[string]]::new()
                while ($j -lt $body.Count -and $body[$j] -notmatch '^[-*]\s+' -and $body[$j] -notmatch '^#') {
                    $l = $body[$j]
                    if ($l -match '^\s+[-*]\s+(.+)$') { $details.Add((ConvertTo-WhatsNewPlain $Matches[1])) }
                    elseif ($l.Trim()) { $cont.Add($l.Trim()) }
                    $j++
                }
                $prefix = ''
                if ($first -match '^\((Preview|GA)\)\s*(.*)$') { $prefix = $Matches[1]; $first = $Matches[2] }
                $full = (@($first) + $cont.ToArray()) -join ' '
                $bold = [regex]::Match($first, '\*\*(.+?)\*\*')
                $title = if ($bold.Success -and $bold.Index -lt 200) { ConvertTo-WhatsNewPlain $bold.Groups[1].Value } else {
                    $plain = ConvertTo-WhatsNewPlain $first
                    $stop = $plain.IndexOfAny([char[]]'.:')
                    if ($stop -gt 20 -and $stop -lt 160) { $plain.Substring(0, $stop) } elseif ($plain.Length -gt 140) { $plain.Substring(0, $plain.LastIndexOf(' ', 140)) } else { $plain }
                }
                $summary = ConvertTo-WhatsNewPlain $full
                $firstLink = [regex]::Match($full, '\]\(([^)\s]+)\)')
                $status = Get-WhatsNewStatus -Title $title -Text $summary -Prefix $prefix
                [pscustomobject]@{
                    Product   = $Product
                    Month     = $month.Month
                    Title     = $title
                    Status    = $status
                    Summary   = $summary
                    Details   = $details.ToArray()
                    Link      = $monthLink
                    LearnMore = $(if ($firstLink.Success) { Resolve-WhatsNewLink -Href $firstLink.Groups[1].Value -PageUrl $PageUrl } else { $null })
                    Deadline  = $(if ($status -in 'Retiring', 'Action needed') { Get-WhatsNewDeadline -Text $summary } else { $null })
                }
            }
        }
    }
}

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
            $kept = @(ConvertFrom-WhatsNewMarkdown -Markdown ([string]$resp.Content) -Product $s.Product -PageUrl $s.Url | Where-Object { [string]::CompareOrdinal($_.Month, $since) -ge 0 })
            foreach ($k in $kept) { $items.Add($k) }
            [pscustomobject]@{ Product = $s.Product; Url = $s.Url; Ok = $true; Error = $null; Items = $kept.Count }
        }
        catch {
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

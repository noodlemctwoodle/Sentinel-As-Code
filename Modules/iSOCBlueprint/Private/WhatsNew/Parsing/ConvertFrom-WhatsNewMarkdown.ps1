#Requires -Version 7.6

<#
.SYNOPSIS
    The items of one What's new page, from its Markdown.

.NOTES
    File:         Modules/iSOCBlueprint/Private/WhatsNew/Parsing/ConvertFrom-WhatsNewMarkdown.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.1.0
    Last Updated: 2026-11-16
    Component:    iSOC Blueprint, What's new reading
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

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

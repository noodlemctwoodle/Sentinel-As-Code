#Requires -Version 7.6

<#
.SYNOPSIS
    The Markdown summary of a community source's rules.

.DESCRIPTION
    Copied from Build-Readme (Tools/Import-CommunityRules.ps1). The description column shows each
    rule's own first line: the script took the first line of the
    description, which is the attribution every community rule starts with.
    The text names Import-iSOCCommunityRule to re-import (MIGRATION.md edit
    E30).

.NOTES
    File:         Modules/iSOCDeployments/Private/Community/ConvertTo-iSOCCommunityReadme.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function ConvertTo-iSOCCommunityReadme {
    <#
    .SYNOPSIS
        Return the README a community import writes under
        Docs/Content/Community/.

    .DESCRIPTION
        The source's title, attribution and licence, the deployment note,
        a table of categories and rule counts, then a table per category of
        each rule's name, severity and the first line of its description
        after the attribution, with | escaped. Lines end with LF.

    .PARAMETER Source
        The community source.

    .PARAMETER CategoryStats
        The rule count by category.

    .PARAMETER RuleDetails
        By category, each rule's Name, Severity and Description.

    .PARAMETER ImportDate
        When the rules were last synced.

    .OUTPUTS
        [string] The Markdown.

    .EXAMPLE
        ConvertTo-iSOCCommunityReadme -Source $source -CategoryStats $stats -RuleDetails $details -ImportDate $date
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Source,

        [Parameter(Mandatory)]
        [hashtable] $CategoryStats,

        [Parameter(Mandatory)]
        [hashtable] $RuleDetails,

        [Parameter(Mandatory)]
        [string] $ImportDate
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    $add = { param([string[]] $Text) foreach ($line in $Text) { $lines.Add($line) } }
    & $add "# Community Rules: $($Source.Title)", '', '## Attribution', ''
    & $add $Source.About
    & $add '', '## License', ''
    & $add $Source.Licence
    & $add '', '## Deployment Note', ''
    & $add 'These rules deploy as **disabled** by default. Enable individual rules in the',
    'Microsoft Sentinel portal after reviewing them against your environment''s data',
    'sources, retention, and noise tolerance.', ''
    & $add '## Categories', '', '| Category | Rule Count |', '|---|---|'
    foreach ($cat in ($CategoryStats.Keys | Sort-Object)) { $lines.Add("| $cat | $($CategoryStats[$cat]) |") }
    $lines.Add('')

    $escape = { param([string] $Text) $Text -replace '\|', '\|' }
    foreach ($cat in ($RuleDetails.Keys | Sort-Object)) {
        & $add "## $cat", '', '| Name | Severity | Description |', '|---|---|---|'
        foreach ($entry in $RuleDetails[$cat]) {
            $description = [string]$entry.Description
            if ($description.StartsWith($Source.Attribution)) { $description = $description.Substring($Source.Attribution.Length) }
            $firstLine = $description -split "`n" | Where-Object { $_.Trim() -ne '' } | Select-Object -First 1
            if ($null -eq $firstLine) { $firstLine = '' }
            $lines.Add("| $(& $escape $entry.Name) | $(& $escape $entry.Severity) | $(& $escape $firstLine.TrimEnd("`r")) |")
        }
        $lines.Add('')
    }

    & $add '---', '', "Last synced: $ImportDate", '', 'To re-import or update these rules, run:', '', '```powershell'
    & $add "Import-iSOCCommunityRule -Source $($Source.Name)", '```'
    ($lines -join "`n") + "`n"
}

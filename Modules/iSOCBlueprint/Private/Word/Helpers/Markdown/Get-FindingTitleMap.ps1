#Requires -Version 7.6

<#
.SYNOPSIS
    Collect the finding titles from every file, so dense bullets can be split reliably.

.DESCRIPTION
    Helper for the Word report conversion (Invoke-iSOCBlueprintWordConversion).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Word/Helpers/Markdown/Get-FindingTitleMap.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Word report
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-FindingTitleMap {
    <#
    .SYNOPSIS
        Build a map of finding ID to canonical title from gap-analysis headings,
        so the dense overview bullets can be split into title and body.

    .DESCRIPTION
        The headings are shaped like '### [SAC-PLT-02](#sac-plt-02) - Custom log
        table ...'. Reading the titles from the headings means the bullets need
        not be split by guessing at internal dashes. When an ID has more than
        one heading, the first one found wins.

    .PARAMETER Texts
        The Markdown texts of the files to search for headings. Empty texts are
        skipped.

    .OUTPUTS
        [hashtable] Finding ID to title.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)] [string[]] $Texts)

    $map = @{}
    $pattern = '(?m)^#{2,4}[ \t]+\[(?<id>[A-Za-z]+(?:-[A-Za-z]+)?-\d+)\]\([^)]*\)[ \t]*[—–-][ \t]*(?<title>.+?)[ \t]*$'
    foreach ($t in $Texts) {
        if (-not $t) { continue }
        foreach ($m in [regex]::Matches($t, $pattern)) {
            $id = $m.Groups['id'].Value
            if (-not $map.ContainsKey($id)) { $map[$id] = $m.Groups['title'].Value.Trim() }
        }
    }
    return $map
}

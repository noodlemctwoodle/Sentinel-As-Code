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
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, Word report
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-FindingTitleMap {
    <#
    .SYNOPSIS
        Build a map of finding ID -> canonical title from gap-analysis
        headings like '### [SAC-PLT-02](#sac-plt-02) - Custom log table ...',
        so the dense overview bullets can be split into title + body
        without guessing at internal dashes.
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

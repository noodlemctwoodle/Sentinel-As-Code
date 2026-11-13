#Requires -Version 7.6

<#
.SYNOPSIS
    Split dense finding bullets into a title and a description.

.DESCRIPTION
    Helper for the Word report conversion (Invoke-iSOCBlueprintWordConversion).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Word/Helpers/Markdown/Convert-FindingBullets.ps1
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

function Convert-FindingBullets {
    <#
    .SYNOPSIS
        Rewrite dense finding bullets into a bold severity/ID/title lead
        line plus a description paragraph beneath.

    .DESCRIPTION
        Only lines shaped like '- **<sev>** [<ID>](<link>) <rest>' (where
        <ID> is e.g. SAC-PLT-02) are touched - everything else is returned
        verbatim. The title is split from the description using the title
        map where the ID is known, otherwise on the first ' - ' break.
        Returns the rewritten text; increments $Count by the number of
        bullets changed.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string]    $Text,
        [Parameter(Mandatory)] [hashtable] $TitleMap,
        [Parameter(Mandatory)] [ref]       $Count
    )

    $pattern = '(?m)^(?<ind>[ \t]*)[-*][ \t]+\*\*(?<sev>[^*]+?)\*\*[ \t]*\[(?<id>[A-Za-z]+(?:-[A-Za-z]+)?-\d+)\]\((?<link>[^)]+)\)[ \t]*(?<rest>.*\S)[ \t]*$'
    $Count.Value += [regex]::Matches($Text, $pattern).Count

    # Severity word -> character style (defined in the reference doc) so
    # the word itself is coloured.
    $sevStyles = @{
        'critical' = 'SevCritical'; 'high' = 'SevCritical'
        'warning'  = 'SevWarning';  'medium' = 'SevWarning'; 'moderate' = 'SevWarning'
        'low'      = 'SevLow'
        'info'     = 'SevInfo';     'informational' = 'SevInfo'
    }

    $evaluator = {
        param($m)
        $ind  = $m.Groups['ind'].Value
        $sev  = $m.Groups['sev'].Value.Trim()
        $id   = $m.Groups['id'].Value.Trim()
        $link = $m.Groups['link'].Value.Trim()
        $rest = $m.Groups['rest'].Value.Trim()

        $title = $rest
        $desc = ''
        if ($TitleMap.ContainsKey($id) -and $rest.StartsWith($TitleMap[$id])) {
            $title = $TitleMap[$id]
            $desc = $rest.Substring($title.Length).Trim()
            $desc = [regex]::Replace($desc, '^[—–-][ \t]*', '')
        }
        else {
            $sep = [regex]::Match($rest, '[ \t][—–][ \t]')
            if ($sep.Success) {
                $title = $rest.Substring(0, $sep.Index).Trim()
                $desc = $rest.Substring($sep.Index + $sep.Length).Trim()
            }
        }

        $sevWord = ([regex]::Replace($sev, '^[^\p{L}]+', '')).Trim()
        $styleName = $sevStyles[$sevWord.ToLowerInvariant()]
        $sevSeg = if ($styleName) { "[$sevWord]{custom-style=`"$styleName`"}" } else { "**$sevWord**" }

        $lead = "$ind- $sevSeg `u{00B7} **[$id]($link)** `u{00B7} **$title**"
        if ($desc) { return "$lead  `n$ind  $desc" }
        return $lead
    }.GetNewClosure()

    return [regex]::Replace($Text, $pattern, $evaluator)
}

#Requires -Version 7.2

<#
.SYNOPSIS
    One string rewritten so ARM evaluates it back to the same value in the
    target workspace.

.DESCRIPTION
    Copied from ConvertTo-ArmStringValue (847ef86:Tools/Export-Playbooks.ps1).

.NOTES
    File:         Modules/iSOCDeployments/Private/Export/ConvertTo-iSOCArmStringValue.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.0
    Last Updated: 2026-11-03
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function ConvertTo-iSOCArmStringValue {
    <#
    .SYNOPSIS
        Return a string with the portable context's matches made ARM
        expressions.

    .DESCRIPTION
        With no match the string comes back as it is, except that a
        literal starting with [ and ending with ] gets the [[ escape, so
        ARM does not evaluate it. With matches it becomes a concat() of the
        literal pieces (single quotes doubled) and the expressions, or a
        bare expression when the whole string was one match.

    .PARAMETER Value
        The string.

    .PARAMETER Context
        From Get-iSOCPortableContext; its UsedParameters is filled in.

    .OUTPUTS
        [string] The string.

    .EXAMPLE
        ConvertTo-iSOCArmStringValue -Value $uri -Context $portable
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Value,

        [Parameter(Mandatory)]
        [hashtable] $Context
    )

    $hits = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $Context.Rules.Count; $i++) {
        foreach ($m in [regex]::Matches($Value, $Context.Rules[$i].Pattern)) {
            $group = $m.Groups['v']
            $hits.Add([pscustomobject]@{ Start = $group.Index; Length = $group.Length; Priority = $i })
        }
    }

    if ($hits.Count -eq 0) {
        if ($Value.StartsWith('[') -and $Value.EndsWith(']')) { return "[$Value" }
        return $Value
    }

    $parts = [System.Collections.Generic.List[string]]::new()
    $cursor = 0
    foreach ($hit in ($hits | Sort-Object Start, Priority)) {
        if ($hit.Start -lt $cursor) { continue }
        if ($hit.Start -gt $cursor) { $parts.Add("'" + $Value.Substring($cursor, $hit.Start - $cursor).Replace("'", "''") + "'") }
        $rule = $Context.Rules[$hit.Priority]
        $parts.Add($rule.Expression)
        if ($rule.Parameter) { [void]$Context.UsedParameters.Add($rule.Parameter) }
        $cursor = $hit.Start + $hit.Length
    }
    if ($cursor -lt $Value.Length) { $parts.Add("'" + $Value.Substring($cursor).Replace("'", "''") + "'") }

    if ($parts.Count -eq 1) { return "[$($parts[0])]" }
    "[concat($($parts -join ', '))]"
}

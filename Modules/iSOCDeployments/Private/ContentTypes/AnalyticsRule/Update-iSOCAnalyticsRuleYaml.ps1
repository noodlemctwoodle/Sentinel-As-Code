#Requires -Version 7.2

<#
.SYNOPSIS
    UpdateRepoFile handler for analytics rules: write a rule's workspace
    values into its YAML file.

.DESCRIPTION
    Copied from Update-RuleYamlFile (Tools/Test-SentinelRuleDrift.ps1). The
    values written are the workspace's as it returns them; the script wrote
    the forms it compared, so a query edited in the portal went into the
    file as one whitespace-collapsed line. Replacements are made literally,
    so a value with $ sequences in it (a KQL join's $left, say) is written
    as it is (MIGRATION.md edit E22).

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/AnalyticsRule/Update-iSOCAnalyticsRuleYaml.ps1
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

function Update-iSOCAnalyticsRuleYaml {
    <#
    .SYNOPSIS
        Rewrite the changed fields of a rule file in place, and say whether
        the file changed.

    .DESCRIPTION
        Each single-line field (name, severity, queryFrequency, queryPeriod,
        triggerOperator in its short form, triggerThreshold) is replaced on
        its own line; the query: | block is replaced whole, up to the next
        top-level key, each line indented two spaces. Everything else in the
        file is left byte for byte. When a field was changed, the patch part
        of version: is raised, so smart deployment sends the rule again. A
        field the file has no line for is not added, and the function then
        returns $false. The file is written as UTF-8 without a byte order
        mark, its line endings as they were: the script's name and severity
        patterns took a CRLF line's carriage return with them.

    .PARAMETER Path
        The rule file.

    .PARAMETER Modification
        The differences, from Compare-iSOCContentBody: Field and Deployed.

    .OUTPUTS
        [bool] $true when the file changed.

    .EXAMPLE
        Update-iSOCAnalyticsRuleYaml -Path $item.SourcePath -Modification $item.Modifications
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Sync-iSOCContent checks ShouldProcess before it calls this.')]
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Modification
    )

    $original = Get-Content -LiteralPath $Path -Raw
    $text = $original
    $newline = if ($original -match "`r`n") { "`r`n" } else { "`n" }
    # Every $ doubled, so .NET reads the replacement literally.
    $replace = {
        param([string] $Pattern, [string] $Replacement)
        [regex]::Replace($text, $Pattern, $Replacement.Replace('$', '$$'))
    }

    foreach ($mod in $Modification) {
        $newValue = $mod.Deployed
        if ($null -eq $newValue) { continue }
        $value = [string]$newValue
        switch ([string]$mod.Field) {
            'severity' { $text = & $replace '(?m)^severity:[ \t]*\S[^\r\n]*' "severity: $value" }
            'displayName' {
                $needsQuoting = $value -match '[:#\[\]\{\}&*!|>''""%@`,]' -or $value -match '^\s|\s$'
                $rendered = if ($needsQuoting) { "'" + ($value -replace "'", "''") + "'" } else { $value }
                $text = & $replace '(?m)^name:[ \t]*\S[^\r\n]*' "name: $rendered"
            }
            'queryFrequency' { $text = & $replace '(?m)^queryFrequency:[ \t]*\S+' "queryFrequency: $value" }
            'queryPeriod' { $text = & $replace '(?m)^queryPeriod:[ \t]*\S+' "queryPeriod: $value" }
            'triggerOperator' { $text = & $replace '(?m)^triggerOperator:[ \t]*\S+' "triggerOperator: $(ConvertTo-iSOCShortTriggerOperator $value)" }
            'triggerThreshold' { $text = & $replace '(?m)^triggerThreshold:[ \t]*\S+' "triggerThreshold: $value" }
            'query' {
                # The block runs to the next top-level key. Without (?s), '.'
                # stays on one line, so the match cannot swallow the sections
                # after the query.
                $indented = (($value.TrimEnd("`r", "`n") -split "`r?`n") | ForEach-Object { "  $_" }) -join $newline
                $text = & $replace '(?m)^query:[ \t]*\|[^\r\n]*\r?\n(?:[ \t][^\r\n]*\r?\n?)*?(?=^[A-Za-z][\w-]*:)' "query: |$newline$indented$newline"
            }
        }
    }

    if ($text -ne $original -and $text -match '(?m)^version:[ \t]*([0-9]+)\.([0-9]+)\.([0-9]+)\b') {
        $newVersion = "$($Matches[1]).$($Matches[2]).$([int]$Matches[3] + 1)"
        $text = & $replace '(?m)^version:[ \t]*[0-9]+\.[0-9]+\.[0-9]+\b' "version: $newVersion"
    }

    if ($text -ne $original) {
        [System.IO.File]::WriteAllText($Path, $text, [System.Text.UTF8Encoding]::new($false))
        return $true
    }
    $false
}

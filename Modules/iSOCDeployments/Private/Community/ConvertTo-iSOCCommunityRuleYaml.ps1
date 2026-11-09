#Requires -Version 7.6

<#
.SYNOPSIS
    A community rule normalised to the repository's conventions, as YAML.

.DESCRIPTION
    Copied from Build-RuleYaml (Tools/Import-CommunityRules.ps1). The trigger operator goes through
    ConvertTo-iSOCTriggerOperator, the one map the module keeps, which also
    writes a long spelling in the API's case (MIGRATION.md edit E28).

.NOTES
    File:         Modules/iSOCDeployments/Private/Community/ConvertTo-iSOCCommunityRuleYaml.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    Needs powershell-yaml when it runs. Import-iSOCYamlModule loads it
    then instead of #Requires, so the module imports without it.
#>

# Keeps the file help above from being read as the help of the function below.

function ConvertTo-iSOCCommunityRuleYaml {
    <#
    .SYNOPSIS
        Validate a parsed community rule, normalise it, and return its
        YAML.

    .DESCRIPTION
        The rule needs id, name, kind, severity and query, or it throws.
        It is set disabled (community rules deploy disabled), the source's
        attribution goes before its description, its tags gain the source's,
        and a short trigger operator (gt, lt, eq, ne) becomes the API's
        name. An ordered rule keeps its key order. The dictionary given is
        changed in place.

    .PARAMETER Rule
        The rule, parsed.

    .PARAMETER SourceFile
        Where it came from, for the error.

    .PARAMETER Source
        The community source, from Get-iSOCCommunitySource.

    .OUTPUTS
        [string] The YAML, ending with one newline.

    .EXAMPLE
        ConvertTo-iSOCCommunityRuleYaml -Rule $rule -SourceFile $path -Source $source
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Rule,

        [Parameter(Mandatory)]
        [string] $SourceFile,

        [Parameter(Mandatory)]
        [hashtable] $Source
    )

    $missing = @('id', 'name', 'kind', 'severity', 'query' | Where-Object { -not $Rule.Contains($_) -or [string]::IsNullOrWhiteSpace($Rule[$_]) })
    if ($missing.Count -gt 0) { throw "Rule in '$SourceFile' is missing required fields: $($missing -join ', ')" }

    $Rule['enabled'] = $false
    $existing = if ($Rule.Contains('description')) { $Rule['description'] } else { '' }
    $Rule['description'] = $Source.Attribution + $existing
    $Rule['tags'] = @(Merge-iSOCCommunityTag -Existing $(if ($Rule.Contains('tags')) { $Rule['tags'] } else { @() }) -Required $Source.Tags)
    if ($Rule.Contains('triggerOperator') -and $Rule['triggerOperator']) { $Rule['triggerOperator'] = ConvertTo-iSOCTriggerOperator ([string]$Rule['triggerOperator']) }

    Import-iSOCYamlModule
    ConvertTo-Yaml $Rule
}

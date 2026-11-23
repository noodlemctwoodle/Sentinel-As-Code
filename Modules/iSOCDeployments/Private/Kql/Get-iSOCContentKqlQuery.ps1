#Requires -Version 7.6

<#
.SYNOPSIS
    The KQL embedded in a content file.

.DESCRIPTION
    Copied from Get-ContentKqlQuery in Modules/Sentinel.Common/Sentinel.Common.psm1
    (1.1.1) with the helper names changed and the logic unchanged, apart
    from loading powershell-yaml itself (MIGRATION.md edit E4).
    Its answer for every file under Content/ was held to the original's on
    release/26.11.0, until Sentinel.Common was removed;
    Tests/iSOCDeployments/Kql.Tests.ps1 now holds it to the answers the
    original gave.

.NOTES
    File:         Modules/iSOCDeployments/Private/Kql/Get-iSOCContentKqlQuery.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-23
    Version:      0.1.2
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCContentKqlQuery {
    <#
.SYNOPSIS
    Read a content file and return its embedded KQL query text. Supports
    AnalyticalRules / HuntingQueries / Parsers (YAML, `query:` field) and
    SummaryRules (JSON, `query:` field) and DefenderCustomDetections
    (YAML, `queryCondition.queryText`).

.OUTPUTS
    String containing the KQL, or $null if the file does not match any
    known content shape or has no embedded query.
#>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [string]$Path)

    if (-not (Test-Path $Path)) { return $null }
    Import-iSOCYamlModule
    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    try {
        if ($extension -eq '.yaml' -or $extension -eq '.yml') {
            $yaml = ConvertFrom-Yaml (Get-Content -Path $Path -Raw -ErrorAction Stop)
            if ($null -eq $yaml -or -not ($yaml -is [System.Collections.IDictionary])) { return $null }

            # Defender custom detections nest the query under queryCondition.
            if ($yaml.ContainsKey('queryCondition') -and ($yaml['queryCondition'] -is [System.Collections.IDictionary]) -and $yaml['queryCondition'].ContainsKey('queryText')) {
                return [string]$yaml['queryCondition']['queryText']
            }
            if ($yaml.ContainsKey('query')) {
                return [string]$yaml['query']
            }
        } elseif ($extension -eq '.json') {
            $json = Get-Content -Path $Path -Raw -ErrorAction Stop | ConvertFrom-Json -Depth 32
            if ($json.PSObject.Properties.Name -contains 'query') {
                return [string]$json.query
            }
        }
    } catch {
        # Per-file content-schema test owns parse errors; this helper
        # silently returns $null when extraction fails.
        Write-Verbose "No KQL read from '$Path': the content-schema test owns parse errors."
    }
    return $null
}

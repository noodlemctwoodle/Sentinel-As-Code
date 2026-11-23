#Requires -Version 7.6

<#
.SYNOPSIS
    Map every analytics rule to the tables its query reads

.DESCRIPTION
    Split from Get-KqlTableReferences.ps1 so each file holds one function.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Kql/Get-RuleTableReferences.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-09
    Version:      0.1.0
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+, SentinelCommon.Kql.ps1 (dot-sourced by the caller)

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-RuleTableReferences {
    <#
    .SYNOPSIS
        Map every analytics rule to the tables its query reads.

    .PARAMETER AlertRules
        Alert rule objects as the Sentinel REST API returns them
        (name, kind, properties.displayName, properties.enabled,
        properties.query).

    .OUTPUTS
        [pscustomobject[]] RuleId, RuleName, Kind, Enabled, Tables.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param([Parameter(Mandatory = $false)] [AllowNull()] [object[]] $AlertRules)

    $rows = foreach ($rule in @($AlertRules)) {
        if ($null -eq $rule) { continue }
        $props = Get-KqlPropertyValue $rule 'properties'
        [pscustomobject]@{
            RuleId   = [string](Get-KqlPropertyValue $rule 'name' '')
            RuleName = [string](Get-KqlPropertyValue $props 'displayName' '')
            Kind     = [string](Get-KqlPropertyValue $rule 'kind' '')
            Enabled  = [bool](Get-KqlPropertyValue $props 'enabled' $false)
            Tables   = @(Resolve-KqlTableNames -Query ([string](Get-KqlPropertyValue $props 'query' '')))
        }
    }
    return @($rows)
}

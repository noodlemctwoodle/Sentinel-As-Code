#Requires -Version 7.6

<#
.SYNOPSIS
    Map every rule template to the tables it needs, and flag templates that are deprecated or...

.DESCRIPTION
    Split from Get-KqlTableReferences.ps1 so each file holds one function.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Kql/Get-TemplateTableReference.ps1
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

function Get-TemplateTableReference {
    <#
    .SYNOPSIS
        Map every rule template to the tables it needs, and flag templates
        that are deprecated or already deployed.

    .PARAMETER Templates
        Alert rule template objects as the REST API returns them.

    .PARAMETER AlertRules
        The workspace's alert rules, used to detect templates that are
        already deployed through alertRuleTemplateName.

    .OUTPUTS
        [pscustomobject[]] TemplateId, DisplayName, Kind, Severity, Tactics,
        AlreadyDeployed, Deprecated, Tables.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]], [object[]])]
    param(
        [Parameter(Mandatory = $false)] [AllowNull()] [object[]] $Templates,
        [Parameter(Mandatory = $false)] [AllowNull()] [object[]] $AlertRules
    )

    $deployedTemplateNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($rule in @($AlertRules)) {
        if ($null -eq $rule) { continue }
        $tplName = Get-KqlPropertyValue (Get-KqlPropertyValue $rule 'properties') 'alertRuleTemplateName'
        if (-not [string]::IsNullOrWhiteSpace($tplName)) { [void]$deployedTemplateNames.Add([string]$tplName) }
    }

    $rows = foreach ($tpl in @($Templates)) {
        if ($null -eq $tpl) { continue }
        $props = Get-KqlPropertyValue $tpl 'properties'
        $templateId = [string](Get-KqlPropertyValue $tpl 'name' '')
        $displayName = [string](Get-KqlPropertyValue $props 'displayName' '')
        $createdCount = 0
        $rawCount = Get-KqlPropertyValue $props 'alertRulesCreatedByTemplateCount' 0
        [void][int]::TryParse([string]$rawCount, [ref]$createdCount)

        $dataTypes = [System.Collections.Generic.List[string]]::new()
        foreach ($rdc in @(Get-KqlPropertyValue $props 'requiredDataConnectors' @())) {
            foreach ($dt in @(Get-KqlPropertyValue $rdc 'dataTypes' @())) {
                if (-not [string]::IsNullOrWhiteSpace($dt)) { $dataTypes.Add([string]$dt) }
            }
        }

        [pscustomobject]@{
            TemplateId      = $templateId
            DisplayName     = $displayName
            Kind            = [string](Get-KqlPropertyValue $tpl 'kind' '')
            Severity        = [string](Get-KqlPropertyValue $props 'severity' '')
            Tactics         = @(Get-KqlPropertyValue $props 'tactics' @() | ForEach-Object { [string]$_ })
            AlreadyDeployed = ($deployedTemplateNames.Contains($templateId) -or $createdCount -gt 0)
            Deprecated      = ($displayName -match '(?i)\bdeprecated\b')
            Tables          = @(Resolve-KqlTableName -Query ([string](Get-KqlPropertyValue $props 'query' '')) -DataTypes $dataTypes.ToArray())
        }
    }
    return @($rows)
}

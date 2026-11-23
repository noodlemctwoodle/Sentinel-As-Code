#Requires -Version 7.6

<#
.SYNOPSIS
    ToRequest handler for analytics rules: the body deploy sends.

.DESCRIPTION
    Copied from the body builder inside Deploy-CustomDetections
    (Deploy/content/Deploy-CustomContent.ps1), unchanged in what it sends.
    Tests/iSOCDeployments/AnalyticsRule.Tests.ps1 runs both over every rule
    in Content/AnalyticalRules/ and compares the requests.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/AnalyticsRule/ConvertTo-iSOCAnalyticsRuleRequest.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-23
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function ConvertTo-iSOCAnalyticsRuleRequest {
    <#
    .SYNOPSIS
        Build the alert rule request body for one rule file.

    .DESCRIPTION
        Builds { kind, properties } from the rule as Deploy-CustomContent.ps1
        does:

        - enabled is false for a Community rule and with -Disabled, else the
          file's enabled, else true;
        - suppression is off for five hours unless the file says otherwise;
        - a Scheduled rule carries its frequency, period, threshold and
          operator, the operator mapped to the API spelling;
        - relevantTechniques (or techniques) are split into parent
          techniques and sub-techniques;
        - entity mappings, custom details, alert details override, event
          grouping and incident configuration are passed through when the
          file has them.

        The function reads nothing outside the item and sends nothing; the
        caller joins ResourceName to the content type's collection.

    .PARAMETER Item
        A repository item from Read-iSOCAnalyticsRuleRepo that passed
        Test-iSOCAnalyticsRule.

    .PARAMETER Disabled
        Send the rule disabled whatever the file says, as deploy does when a
        dependency is missing.

    .OUTPUTS
        [pscustomobject] iSOCDeployments.Request: ContentType, Identity,
        ResourceName (the id as written) and Body.

    .EXAMPLE
        $request = ConvertTo-iSOCAnalyticsRuleRequest -Item $item
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Item,

        [switch] $Disabled
    )

    $rule = $Item.Data
    $ruleKind = $rule['kind']
    $isCommunityRule = $Item.Source -eq 'Community'

    $ruleDescription = if ($rule.Contains('description')) { $rule['description'] } else { '' }
    $ruleEnabled = if ($isCommunityRule) { $false } elseif ($Disabled) { $false } elseif ($rule.Contains('enabled')) { [bool]$rule['enabled'] } else { $true }

    $properties = @{
        displayName         = $rule['name']
        description         = $ruleDescription
        severity            = $rule['severity']
        enabled             = $ruleEnabled
        query               = $rule['query']
        suppressionEnabled  = if ($rule.Contains('suppressionEnabled')) { [bool]$rule['suppressionEnabled'] } else { $false }
        suppressionDuration = if ($rule.Contains('suppressionDuration')) { $rule['suppressionDuration'] } else { 'PT5H' }
    }

    if ($ruleKind -eq 'Scheduled') {
        $properties.queryFrequency = $rule['queryFrequency']
        $properties.queryPeriod = $rule['queryPeriod']
        $properties.triggerThreshold = [int]$rule['triggerThreshold']
        $properties.triggerOperator = ConvertTo-iSOCTriggerOperator $rule['triggerOperator']
    }

    # Both 'techniques' and 'relevantTechniques' are read; the Azure-Sentinel
    # repository uses the latter.
    if ($rule.Contains('tactics')) {
        $properties.tactics = [array]$rule['tactics']
    }
    $techKey = if ($rule.Contains('relevantTechniques')) { 'relevantTechniques' } elseif ($rule.Contains('techniques')) { 'techniques' } else { $null }
    if ($techKey) {
        $allTechniques = [array]$rule[$techKey]
        # Parent techniques (T####) go in 'techniques'.
        $properties.techniques = [array]($allTechniques | ForEach-Object { ($_ -split '\.')[0] } | Select-Object -Unique)
        # Sub-techniques (T####.###) go in 'subTechniques', which only the
        # preview alert rules API keeps.
        $subTechs = @($allTechniques | Where-Object { $_ -match '\.' } | Select-Object -Unique)
        if ($subTechs -and $subTechs.Count -gt 0) {
            $properties.subTechniques = $subTechs
        }
    }
    if ($rule.Contains('entityMappings')) {
        $properties.entityMappings = [array]$rule['entityMappings']
    }
    if ($rule.Contains('sentinelEntitiesMappings')) {
        $properties.sentinelEntitiesMappings = [array]$rule['sentinelEntitiesMappings']
    }
    if ($rule.Contains('customDetails')) {
        $properties.customDetails = $rule['customDetails']
    }
    if ($rule.Contains('alertDetailsOverride')) {
        $properties.alertDetailsOverride = $rule['alertDetailsOverride']
    }
    if ($rule.Contains('eventGroupingSettings')) {
        $properties.eventGroupingSettings = $rule['eventGroupingSettings']
    }
    if ($rule.Contains('incidentConfiguration')) {
        $properties.incidentConfiguration = $rule['incidentConfiguration']
    }

    [pscustomobject]@{
        PSTypeName   = 'iSOCDeployments.Request'
        ContentType  = $Item.ContentType
        Identity     = $Item.Identity
        ResourceName = [string]$rule['id']
        Body         = @{
            kind       = $ruleKind
            properties = $properties
        }
    }
}

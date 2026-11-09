#Requires -Version 7.6

<#
.SYNOPSIS
    Build the alert rule body for a Content Hub rule template.

.DESCRIPTION
    Copied from the body builder in Deploy-AnalyticsRules
    (Deploy/content/Deploy-SentinelContentHub.ps1), unchanged in what it
    sends. The template is no longer changed on the way: the script added
    the grouping defaults to the template's own incident configuration.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentHub/ConvertTo-iSOCContentHubRuleRequest.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function ConvertTo-iSOCContentHubRuleRequest {
    <#
    .SYNOPSIS
        Return the kind and properties to PUT for a template's rule.

    .DESCRIPTION
        The template's rule properties, without the ARM template fields the
        alert rules API refuses (apiVersion, type, name, id, dependsOn,
        metadata, contentId, contentKind, contentProductId), linked to the
        template by alertRuleTemplateName and templateVersion:
        - enabled is false with -DisableRules, else the template's, else
          true;
        - an NRT rule has no queryFrequency, queryPeriod, triggerOperator or
          triggerThreshold;
        - entity mappings are a list of at most five, the API's limit;
        - a grouping configuration gets matchingMethod AllEntities when it
          has none and its lookback as an ISO duration (5h becomes PT5H),
          and an empty one becomes AllEntities over PT1H.

    .PARAMETER Record
        From Read-iSOCContentHubRuleTemplate.

    .PARAMETER DisableRules
        Send the rule disabled.

    .OUTPUTS
        [hashtable] kind and properties.

    .EXAMPLE
        $body = ConvertTo-iSOCContentHubRuleRequest -Record $record -DisableRules
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Record,

        [switch] $DisableRules
    )

    $deployProperties = $Record.RuleProperties.PSObject.Copy()
    foreach ($armProp in @('apiVersion', 'type', 'name', 'id', 'dependsOn', 'metadata', 'contentId', 'contentKind', 'contentProductId')) {
        if ($deployProperties.PSObject.Properties.Name -contains $armProp) { $deployProperties.PSObject.Properties.Remove($armProp) }
    }

    if ($DisableRules) {
        $deployProperties | Add-Member -NotePropertyName 'enabled' -NotePropertyValue $false -Force
    }
    elseif (-not ($deployProperties.PSObject.Properties.Name -contains 'enabled')) {
        $deployProperties | Add-Member -NotePropertyName 'enabled' -NotePropertyValue $true -Force
    }

    $deployProperties | Add-Member -NotePropertyName 'alertRuleTemplateName' -NotePropertyValue $Record.TemplateName -Force
    $deployProperties | Add-Member -NotePropertyName 'templateVersion' -NotePropertyValue $Record.TemplateVersion -Force

    if ($Record.Kind -eq 'NRT') {
        foreach ($scheduled in 'queryFrequency', 'queryPeriod', 'triggerOperator', 'triggerThreshold') {
            if ($deployProperties.PSObject.Properties.Name -contains $scheduled) { $deployProperties.PSObject.Properties.Remove($scheduled) }
        }
    }

    if ($deployProperties.PSObject.Properties.Name -contains 'entityMappings') {
        if ($deployProperties.entityMappings -and $deployProperties.entityMappings -isnot [System.Array]) {
            $deployProperties.entityMappings = @($deployProperties.entityMappings)
        }
        if ($deployProperties.entityMappings -and $deployProperties.entityMappings.Count -gt 5) {
            $deployProperties.entityMappings = @($deployProperties.entityMappings | Select-Object -First 5)
        }
    }

    if ($deployProperties.PSObject.Properties.Name -contains 'incidentConfiguration' -and $deployProperties.incidentConfiguration -is [psobject]) {
        $incidentConfig = $deployProperties.incidentConfiguration.PSObject.Copy()
        $deployProperties.incidentConfiguration = $incidentConfig
        if ($incidentConfig.PSObject.Properties.Name -contains 'groupingConfiguration') {
            $groupConfig = $incidentConfig.groupingConfiguration
            if ($groupConfig) {
                $groupConfig = $groupConfig.PSObject.Copy()
                $incidentConfig.groupingConfiguration = $groupConfig
                if (-not ($groupConfig.PSObject.Properties.Name -contains 'matchingMethod')) {
                    $groupConfig | Add-Member -NotePropertyName 'matchingMethod' -NotePropertyValue 'AllEntities' -Force
                }
                if ($groupConfig.PSObject.Properties.Name -contains 'lookbackDuration' -and $groupConfig.lookbackDuration -match '^(\d+)(h|d|m)$') {
                    $timeValue = $Matches[1]
                    $groupConfig.lookbackDuration = switch ($Matches[2]) {
                        'h' { "PT${timeValue}H" }
                        'd' { "P${timeValue}D" }
                        'm' { "PT${timeValue}M" }
                    }
                }
            }
            else {
                $incidentConfig | Add-Member -NotePropertyName 'groupingConfiguration' -NotePropertyValue @{
                    matchingMethod   = 'AllEntities'
                    lookbackDuration = 'PT1H'
                } -Force
            }
        }
    }

    @{
        kind       = $Record.Kind
        properties = $deployProperties
    }
}

#Requires -Version 7.6

<#
.SYNOPSIS
    Translate a rule written with the Graph fields retired on 2026-10-01
    into the current shape.

.DESCRIPTION
    Copied from ConvertFrom-LegacyDetectionRule
    (Deploy/content/Deploy-DefenderDetections.ps1).

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/DefenderDetection/ConvertFrom-iSOCLegacyDefenderDetection.ps1
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

function ConvertFrom-iSOCLegacyDefenderDetection {
    <#
    .SYNOPSIS
        Return the rule in the current shape, and the retired fields it
        used.

    .DESCRIPTION
        isEnabled becomes status, schedule.period becomes
        schedule.frequency, alertTemplate.category and mitreTechniques
        become tactics, impactedAssets becomes entityMappings,
        responseActions becomes automatedActions and
        organizationalScope.scopeNames becomes deviceGroups; the
        lastModifiedDateTime fields are dropped. A rule already in the
        current shape comes back unchanged with no retired fields. Where a
        rule sets both an old field and its replacement, the replacement
        wins and the old field is dropped. An impacted asset or response
        action the converters cannot place throws.

    .PARAMETER Rule
        The rule as the file holds it.

    .OUTPUTS
        [hashtable] Rule (the rule in the current shape) and LegacyFields
        (the names of the retired fields that were translated).

    .EXAMPLE
        $translated = ConvertFrom-iSOCLegacyDefenderDetection -Rule $item.Data
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Rule
    )

    $legacy = [System.Collections.Generic.List[string]]::new()
    $out = [ordered]@{}
    foreach ($key in $Rule.Keys) { $out[$key] = $Rule[$key] }

    if ($out.Contains('isEnabled')) {
        if (-not $out.Contains('status')) { $out['status'] = if ([bool]$out['isEnabled']) { 'enabled' } else { 'disabled' } }
        $out.Remove('isEnabled')
        $legacy.Add('isEnabled')
    }
    if ($out.Contains('lastModifiedDateTime')) {
        $out.Remove('lastModifiedDateTime')
        $legacy.Add('lastModifiedDateTime')
    }

    if ($out['queryCondition'] -is [System.Collections.IDictionary] -and $out['queryCondition'].Contains('lastModifiedDateTime')) {
        $query = [ordered]@{}
        foreach ($key in $out['queryCondition'].Keys) { if ($key -ne 'lastModifiedDateTime') { $query[$key] = $out['queryCondition'][$key] } }
        $out['queryCondition'] = $query
        $legacy.Add('queryCondition.lastModifiedDateTime')
    }

    if ($out['schedule'] -is [System.Collections.IDictionary] -and $out['schedule'].Contains('period')) {
        $schedule = [ordered]@{}
        foreach ($key in $out['schedule'].Keys) { if ($key -ne 'period') { $schedule[$key] = $out['schedule'][$key] } }
        if (-not $schedule.Contains('frequency')) {
            $frequency = ConvertTo-iSOCDefenderDetectionFrequency -Value ([string]$out['schedule']['period'])
            $schedule['frequency'] = if ($frequency) { $frequency } else { [string]$out['schedule']['period'] }
        }
        $out['schedule'] = $schedule
        $legacy.Add('schedule.period')
    }

    if ($out['detectionAction'] -is [System.Collections.IDictionary]) {
        $action = [ordered]@{}
        foreach ($key in $out['detectionAction'].Keys) { $action[$key] = $out['detectionAction'][$key] }

        if ($action['alertTemplate'] -is [System.Collections.IDictionary]) {
            $template = [ordered]@{}
            foreach ($key in $action['alertTemplate'].Keys) { $template[$key] = $action['alertTemplate'][$key] }

            if ($template.Contains('category') -or $template.Contains('mitreTechniques')) {
                if (-not $template.Contains('tactics') -and $template.Contains('category')) {
                    $template['tactics'] = ConvertTo-iSOCDefenderDetectionTactic -Category ([string]$template['category']) -MitreTechniques @($template['mitreTechniques'])
                }
                foreach ($old in 'category', 'mitreTechniques') {
                    if ($template.Contains($old)) { $template.Remove($old); $legacy.Add("alertTemplate.$old") }
                }
            }
            if ($template.Contains('impactedAssets')) {
                if (-not $template.Contains('entityMappings')) {
                    $template['entityMappings'] = ConvertTo-iSOCDefenderDetectionEntityMapping -ImpactedAssets @($template['impactedAssets'])
                }
                $template.Remove('impactedAssets')
                $legacy.Add('alertTemplate.impactedAssets')
            }
            $action['alertTemplate'] = $template
        }

        if ($action.Contains('responseActions')) {
            if (-not $action.Contains('automatedActions')) {
                $action['automatedActions'] = ConvertTo-iSOCDefenderDetectionAutomatedAction -ResponseActions @($action['responseActions'])
            }
            $action.Remove('responseActions')
            $legacy.Add('detectionAction.responseActions')
        }

        if ($action['organizationalScope'] -is [System.Collections.IDictionary] -and $action['organizationalScope'].Contains('scopeNames')) {
            if (-not $action['organizationalScope'].Contains('deviceGroups')) {
                $action['organizationalScope'] = [ordered]@{ deviceGroups = @($action['organizationalScope']['scopeNames']) }
            } else {
                $action['organizationalScope'] = [ordered]@{ deviceGroups = @($action['organizationalScope']['deviceGroups']) }
            }
            $legacy.Add('organizationalScope.scopeNames')
        }

        $out['detectionAction'] = $action
    }

    @{ Rule = $out; LegacyFields = @($legacy) }
}

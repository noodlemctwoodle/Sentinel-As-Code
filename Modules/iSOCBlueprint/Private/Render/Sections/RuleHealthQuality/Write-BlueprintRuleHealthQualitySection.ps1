#Requires -Version 7.6

<#
.SYNOPSIS
    Build the figures for and write 22-rule-health-quality.md.

.DESCRIPTION
    A step of the Blueprint renderer. Steps run in order and pass their results
    to later ones through the render context, so this one may also prepare
    figures that a later page uses.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/RuleHealthQuality/Write-BlueprintRuleHealthQualitySection.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-16
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.
function Write-BlueprintRuleHealthQualitySection {
    <#
    .SYNOPSIS
        Build the figures for and write 22-rule-health-quality.md.

    .PARAMETER Context
        The render context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the render context.
    $analyticsLinks = $Context.analyticsLinks
    $complexitySection = $Context.complexitySection
    $m = $Context.m
    $n = $Context.n
    $ruleHealthSection = $Context.ruleHealthSection
    $rules = $Context.rules
    $staleSection = $Context.staleSection

    # Section 22: rule health and quality. Rules that fail to run, rules hard to
    # trust, and the anti-patterns the health check lists: no entity mappings,
    # alerts that never become incidents, rules nobody has touched in a year.
    $scheduledEnabled22 = @(
        $rules |
            Where-Object {
                $_ -and $_.kind -in @('Scheduled', 'NRT') -and (Get-BlueprintRawProperty (Get-BlueprintRawProperty $_ 'properties') 'enabled' $false)
            }
    )
    $noEntityRows = @($scheduledEnabled22 |
            Where-Object { @(Get-BlueprintRawProperty (Get-BlueprintRawProperty $_ 'properties') 'entityMappings' @() | Where-Object { $_ }).Count -eq 0 } |
            ForEach-Object {
                [pscustomobject]@{
                    Rule     = [string](Get-BlueprintRawProperty $_.properties 'displayName' $_.name)
                    Kind     = $_.kind
                    Severity = [string](Get-BlueprintRawProperty $_.properties 'severity' '')
                }
            } | Sort-Object Rule)
    $alertOnlyRows = @($scheduledEnabled22 | Where-Object {
            $ic = Get-BlueprintRawProperty (Get-BlueprintRawProperty $_ 'properties') 'incidentConfiguration'
            $ic -and $ic.PSObject.Properties['createIncident'] -and -not [bool]$ic.createIncident
        } | ForEach-Object {
            [pscustomobject]@{
                Rule     = [string](Get-BlueprintRawProperty $_.properties 'displayName' $_.name)
                Kind     = $_.kind
                Severity = [string](Get-BlueprintRawProperty $_.properties 'severity' '')
            }
        } | Sort-Object Rule)
    $antiPatternSection = @"

## Rules without entity mappings

Enabled Scheduled and NRT rules that map no entities. Their incidents carry no account, host or IP to pivot on, so they cannot join the investigation graph, entity pages or UEBA, and automation that acts on entities has nothing to act on ([SAC-DET-03]).

$(Format-BlueprintTable -Items $noEntityRows -Columns 'Rule','Kind','Severity' -EmptyMessage $(if ($scheduledEnabled22.Count) { '_Every enabled Scheduled and NRT rule maps at least one entity._' } else { '_No enabled Scheduled or NRT rules._' }))

## Rules that raise alerts without incidents

Enabled Scheduled and NRT rules with incident creation turned off. Their alerts land in ``SecurityAlert`` but never reach the incident queue, so nobody triages them unless something else picks them up ([SAC-MON-01]).

$(Format-BlueprintTable -Items $alertOnlyRows -Columns 'Rule','Kind','Severity' -EmptyMessage '_Every enabled Scheduled and NRT rule creates incidents._')
"@
    Write-BlueprintSection '22-rule-health-quality.md' (@(
            "$(Format-Banner -Title 'Rule Health and Quality')`n`nWhether the analytics rules run, and whether they are built to be trusted and triaged. The rule inventory is in [20-analytics-rules.md](20-analytics-rules.md); how often each rule fires is in [21-rule-performance.md](21-rule-performance.md).",
            $ruleHealthSection,
            $antiPatternSection,
            $staleSection,
            $complexitySection,
            $analyticsLinks) -join [Environment]::NewLine)
}

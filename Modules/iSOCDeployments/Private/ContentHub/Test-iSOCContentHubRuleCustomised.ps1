#Requires -Version 7.6

<#
.SYNOPSIS
    Whether an analytics rule in the workspace has been changed from its
    Content Hub template.

.DESCRIPTION
    Copied from Test-RuleIsCustomised
    (Deploy/content/Deploy-SentinelContentHub.ps1).

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentHub/Test-iSOCContentHubRuleCustomised.ps1
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

function Test-iSOCContentHubRuleCustomised {
    <#
    .SYNOPSIS
        Compare a deployed rule with its template and name what differs.

    .DESCRIPTION
        Compares the query (runs of whitespace as one space), the query
        frequency and period (as durations, so PT24H and P1D agree), the
        trigger threshold and operator, and the severity. A field only one
        side has is not compared. Entity mappings are not compared: the
        service returns them in a different JSON shape from the template, so
        every rule would look changed.

    .PARAMETER ExistingRule
        The rule as the workspace returns it.

    .PARAMETER TemplateProperties
        The rule's properties in the template.

    .OUTPUTS
        [hashtable] IsCustomised and Modifications (the fields that differ).

    .EXAMPLE
        Test-iSOCContentHubRuleCustomised -ExistingRule $rule -TemplateProperties $record.RuleProperties
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [object] $ExistingRule,

        [Parameter(Mandatory)]
        [object] $TemplateProperties
    )

    $isCustomised = $false
    $modifications = @()
    $existingProps = $ExistingRule.properties
    $both = { param([string] $Name) ($existingProps.PSObject.Properties.Name -contains $Name) -and ($TemplateProperties.PSObject.Properties.Name -contains $Name) }

    if (& $both 'query') {
        $existingQuery = ($existingProps.query -replace '\s+', ' ').Trim()
        $templateQuery = ($TemplateProperties.query -replace '\s+', ' ').Trim()
        if ($existingQuery -ne $templateQuery) {
            $isCustomised = $true
            $modifications += 'KQL query'
        }
    }

    foreach ($duration in 'queryFrequency', 'queryPeriod') {
        if ((& $both $duration) -and (ConvertTo-iSOCCanonicalDuration $existingProps.$duration) -ne (ConvertTo-iSOCCanonicalDuration $TemplateProperties.$duration)) {
            $isCustomised = $true
            $modifications += $duration
        }
    }

    foreach ($field in 'triggerThreshold', 'triggerOperator', 'severity') {
        if ((& $both $field) -and $existingProps.$field -ne $TemplateProperties.$field) {
            $isCustomised = $true
            $modifications += $field
        }
    }

    @{
        IsCustomised  = $isCustomised
        Modifications = $modifications
    }
}

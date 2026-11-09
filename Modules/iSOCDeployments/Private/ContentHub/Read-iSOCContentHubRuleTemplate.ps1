#Requires -Version 7.6

<#
.SYNOPSIS
    Read the rule out of one analytics rule content template.

.DESCRIPTION
    Copied from the template parsing in Deploy-AnalyticsRules
    (Deploy/content/Deploy-SentinelContentHub.ps1).

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentHub/Read-iSOCContentHubRuleTemplate.ps1
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

function Read-iSOCContentHubRuleTemplate {
    <#
    .SYNOPSIS
        Return the rule a template carries, or why it carries none.

    .DESCRIPTION
        The rule is the first resource of the template's mainTemplate. Its
        kind is the resource's (Scheduled when it has none). The template is
        named by its contentId, else the resource's name, which can be an
        ARM expression. Its version is the second resource's (the metadata
        resource), else the template's own.

    .PARAMETER Template
        A content template, read with its mainTemplate.

    .OUTPUTS
        [hashtable] Problem (why the template carries no rule; empty when it
        does), Template, Name (the template's display name, for the log),
        DisplayName, Severity, Kind, TemplateName, TemplateVersion,
        PackageId and RuleProperties.

    .EXAMPLE
        $record = Read-iSOCContentHubRuleTemplate -Template $template
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Template
    )

    $props = $Template.properties
    $record = @{
        Problem         = ''
        Template        = $Template
        Name            = if ($props.PSObject.Properties.Name -contains 'displayName') { $props.displayName } else { $Template.name }
        DisplayName     = $null
        Severity        = $null
        Kind            = 'Scheduled'
        TemplateName    = $null
        TemplateVersion = $null
        PackageId       = if ($props.PSObject.Properties.Name -contains 'packageId') { $props.packageId } else { $null }
        RuleProperties  = $null
    }

    if (-not (($props.PSObject.Properties.Name -contains 'mainTemplate') -and ($null -ne $props.mainTemplate))) {
        $record.Problem = 'the template has no mainTemplate'
        return $record
    }
    $mainTemplate = $props.mainTemplate
    $hasResources = ($mainTemplate.PSObject.Properties.Name -contains 'resources') -and ($null -ne $mainTemplate.resources) -and (@($mainTemplate.resources).Count -gt 0)
    if (-not $hasResources) {
        $record.Problem = 'the template has no resources'
        return $record
    }

    $templateResources = @($mainTemplate.resources)
    $firstResource = $templateResources[0]
    if (-not (($firstResource.PSObject.Properties.Name -contains 'properties') -and ($null -ne $firstResource.properties))) {
        $record.Problem = 'the rule resource has no properties'
        return $record
    }

    $ruleProperties = $firstResource.properties
    $record.RuleProperties = $ruleProperties
    $record.DisplayName = if ($ruleProperties.PSObject.Properties.Name -contains 'displayName') { $ruleProperties.displayName } else { $null }
    $record.Severity = if ($ruleProperties.PSObject.Properties.Name -contains 'severity') { $ruleProperties.severity } else { $null }
    if ($firstResource.PSObject.Properties.Name -contains 'kind') { $record.Kind = $firstResource.kind }

    $templateContentId = if ($props.PSObject.Properties.Name -contains 'contentId') { $props.contentId } else { $null }
    $record.TemplateName = if ($templateContentId) { $templateContentId } elseif ($firstResource.PSObject.Properties.Name -contains 'name') { $firstResource.name } else { $null }

    $record.TemplateVersion = if ($props.PSObject.Properties.Name -contains 'version') { $props.version } else { $null }
    if ($templateResources.Count -gt 1) {
        $secondResource = $templateResources[1]
        if ($secondResource.PSObject.Properties.Name -contains 'properties' -and
            $null -ne $secondResource.properties -and
            $secondResource.properties.PSObject.Properties.Name -contains 'version') {
            $record.TemplateVersion = $secondResource.properties.version
        }
    }

    $record
}

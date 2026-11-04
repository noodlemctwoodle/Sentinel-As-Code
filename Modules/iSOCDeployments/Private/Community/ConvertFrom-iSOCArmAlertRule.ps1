#Requires -Version 7.2

<#
.SYNOPSIS
    One ARM alertRules resource as a normalised community rule.

.DESCRIPTION
    Copied from ConvertFrom-ArmAlertRule (Tools/Import-CommunityRules.ps1). A resource with no
    alertRuleTemplateName takes the id it is given; the script gave it a new
    random GUID on every run (MIGRATION.md edit E31).

.NOTES
    File:         Modules/iSOCDeployments/Private/Community/ConvertFrom-iSOCArmAlertRule.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.0
    Last Updated: 2026-11-04
    Requires:     PowerShell 7.2+

    Needs powershell-yaml when it runs. Import-iSOCYamlModule loads it
    then instead of #Requires, so the module imports without it.
#>

# Keeps the file help above from being read as the help of the function below.

function ConvertFrom-iSOCArmAlertRule {
    <#
    .SYNOPSIS
        Return the YAML of a community rule made from an ARM alertRules
        resource.

    .DESCRIPTION
        The id is the resource's alertRuleTemplateName, else -FallbackId;
        the name its displayName, else the template name, else UnknownRule;
        the kind Scheduled and the severity Medium when the resource has
        none. Shorthand durations become ISO 8601. Tactics, techniques,
        entity mappings, custom details, the alert details override and the
        incident configuration are carried when set. Then the rule is
        normalised as a YAML rule is.

    .PARAMETER Resource
        The resource from the template.

    .PARAMETER SourceFile
        The template, for the error.

    .PARAMETER Source
        The community source.

    .PARAMETER FallbackId
        The id for a resource with no alertRuleTemplateName.

    .OUTPUTS
        [string] The YAML.

    .EXAMPLE
        ConvertFrom-iSOCArmAlertRule -Resource $resource -SourceFile $file -Source $source -FallbackId $id
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Resource,

        [Parameter(Mandatory)]
        [string] $SourceFile,

        [Parameter(Mandatory)]
        [hashtable] $Source,

        [Parameter(Mandatory)]
        [string] $FallbackId
    )

    $p = Get-iSOCPropertyValue -InputObject $Resource -Path 'properties'
    $get = { param([string] $Name) Get-iSOCPropertyValue -InputObject $p -Path $Name }
    $first = { param($A, $B) if ($null -ne $A) { $A } else { $B } }

    $rule = [ordered]@{}
    $rule['id'] = & $first (& $get 'alertRuleTemplateName') $FallbackId
    $rule['name'] = & $first (& $get 'displayName') (& $first (& $get 'alertRuleTemplateName') 'UnknownRule')
    $rule['kind'] = & $first (Get-iSOCPropertyValue -InputObject $Resource -Path 'kind') 'Scheduled'
    $rule['description'] = & $first (& $get 'description') ''
    $rule['severity'] = & $first (& $get 'severity') 'Medium'
    $rule['query'] = & $first (& $get 'query') ''

    if (& $get 'queryFrequency') { $rule['queryFrequency'] = ConvertTo-iSOCIsoDuration (& $get 'queryFrequency') }
    if (& $get 'queryPeriod') { $rule['queryPeriod'] = ConvertTo-iSOCIsoDuration (& $get 'queryPeriod') }
    if (& $get 'triggerOperator') { $rule['triggerOperator'] = & $get 'triggerOperator' }
    if ($null -ne (& $get 'triggerThreshold')) { $rule['triggerThreshold'] = & $get 'triggerThreshold' }

    $tactics = & $get 'tactics'
    if ($tactics -and @($tactics).Count -gt 0) { $rule['tactics'] = @($tactics) }
    $techniques = & $get 'techniques'
    if ($techniques -and @($techniques).Count -gt 0) { $rule['techniques'] = @($techniques) }
    foreach ($name in 'entityMappings', 'customDetails', 'alertDetailsOverride', 'incidentConfiguration') {
        $value = Get-iSOCPropertyValue -InputObject $p -Path $name
        if ($value) { $rule[$name] = $value }
    }

    ConvertTo-iSOCCommunityRuleYaml -Rule $rule -SourceFile $SourceFile -Source $Source
}

#Requires -Version 7.6

<#
.SYNOPSIS
    Link an analytics rule to the Content Hub solution that ships it.

.DESCRIPTION
    Copied from Write-RuleMetadata (Deploy/content/Deploy-SentinelContentHub.ps1).
    Under -WhatIf nothing is written; the script wrote the link for every
    unchanged rule even under its -WhatIf switch (MIGRATION.md edit E19).

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentHub/Set-iSOCContentHubRuleMetadata.ps1
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

function Set-iSOCContentHubRuleMetadata {
    <#
    .SYNOPSIS
        Write the metadata record that shows a rule under its solution in
        Content Hub, and say how it went.

    .DESCRIPTION
        The record is analyticsrule-<rule name>: the template's contentId,
        the rule as parent, the template version (1.0.0 when there is none)
        and the solution as source. A template with no packageId, or one
        whose solution is not among those requested, is not linked, with a
        warning. A failed write is a warning too; the rule stays deployed.
        The record's body is logged at debug level only, since it holds the
        rule's resource id.

    .PARAMETER Context
        The workspace context.

    .PARAMETER Template
        The content template the rule came from.

    .PARAMETER RuleId
        The rule's resource id.

    .PARAMETER RuleName
        The rule's name (its id within the workspace).

    .PARAMETER TemplateName
        The template's contentId.

    .PARAMETER TemplateVersion
        The template's version.

    .PARAMETER Lookup
        From Get-iSOCContentHubSolutionLookup.

    .PARAMETER DisplayName
        The rule's display name, for the log.

    .OUTPUTS
        [string] Linked, Failed, Skipped or WhatIf.

    .EXAMPLE
        Set-iSOCContentHubRuleMetadata -Context $ctx -Template $t -RuleId $rule.id -RuleName $rule.name -TemplateName $id -TemplateVersion $v -Lookup $lookup -DisplayName $name
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Metadata is the name of the Sentinel resource it writes.')]
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Context,

        [Parameter(Mandatory)]
        [psobject] $Template,

        [Parameter(Mandatory)]
        [string] $RuleId,

        [Parameter(Mandatory)]
        [string] $RuleName,

        [string] $TemplateName,

        [string] $TemplateVersion,

        [Parameter(Mandatory)]
        [hashtable] $Lookup,

        [string] $DisplayName
    )

    $pkgId = if ($Template.properties.PSObject.Properties.Name -contains 'packageId') { $Template.properties.packageId } else { $null }
    if (-not $pkgId) {
        Write-iSOCLog "    Metadata skip: no packageId for $DisplayName" -Level Warning
        return 'Skipped'
    }

    if ($Lookup.Detail.ContainsKey($pkgId)) {
        $solDisplayName = $Lookup.Detail[$pkgId].Name
        $solContentId = $Lookup.Detail[$pkgId].ContentId
    }
    elseif ($Lookup.ById.ContainsKey($pkgId)) {
        $solDisplayName = $Lookup.ById[$pkgId]
        $solContentId = $pkgId
    }
    else {
        Write-iSOCLog "    Metadata skip: packageId '$pkgId' not in solution lookup for $DisplayName" -Level Warning
        return 'Skipped'
    }

    if ($RuleId -and -not $RuleId.StartsWith('/')) { $RuleId = "/$RuleId" }

    $metaBody = @{
        properties = @{
            contentId = $TemplateName
            parentId  = $RuleId
            kind      = 'AnalyticsRule'
            version   = if ($TemplateVersion) { $TemplateVersion } else { '1.0.0' }
            source    = @{
                kind     = 'Solution'
                name     = $solDisplayName
                sourceId = $solContentId
            }
        }
    }

    if (-not $PSCmdlet.ShouldProcess($DisplayName, "Link to Content Hub solution '$solDisplayName'")) {
        Write-iSOCLog "    [WhatIf] Would link metadata: $DisplayName -> $solDisplayName"
        return 'WhatIf'
    }

    $metaPath = "$($Context.WorkspaceResourceId)/providers/Microsoft.SecurityInsights/metadata/analyticsrule-$RuleName"
    try {
        Invoke-iSOCRestRequest -Method PUT -Path $metaPath -ApiVersion (Get-iSOCApiVersion SecurityInsights) -Body $metaBody | Out-Null
        Write-iSOCLog "    Metadata linked: $DisplayName -> $solDisplayName"
        'Linked'
    }
    catch {
        Write-iSOCLog "    Metadata FAILED for $DisplayName : $($_.Exception.Message)" -Level Warning
        Write-iSOCLog "    Metadata body: $(ConvertTo-Json -InputObject $metaBody -Depth 10 -Compress)" -Level Debug
        'Failed'
    }
}

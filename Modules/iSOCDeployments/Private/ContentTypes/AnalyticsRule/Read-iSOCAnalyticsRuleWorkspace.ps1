#Requires -Version 7.6

<#
.SYNOPSIS
    ReadWorkspace handler for analytics rules: every rule the workspace has.

.DESCRIPTION
    Copied from Get-ExistingAnalyticsRules (Tools/Test-SentinelRuleDrift.ps1).
    The rules are read with the preview alert rules API, the one the
    deployers write them with: every GA version leaves out subTechniques,
    so a rule absorbed into the repository would lose its sub-techniques.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/AnalyticsRule/Read-iSOCAnalyticsRuleWorkspace.ps1
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

function Read-iSOCAnalyticsRuleWorkspace {
    <#
    .SYNOPSIS
        List the workspace's analytics rules, every page.

    .PARAMETER Context
        The workspace context.

    .PARAMETER ContentType
        The analytics rule content type.

    .OUTPUTS
        [psobject] The rules as the API returns them.

    .EXAMPLE
        $deployed = @(Read-iSOCAnalyticsRuleWorkspace -Context $ctx -ContentType $rules)
    #>
    [CmdletBinding()]
    [OutputType([psobject])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Context,

        [Parameter(Mandatory)]
        [psobject] $ContentType
    )

    Write-iSOCLog 'Fetching deployed Analytics Rules...'
    $rules = @(Invoke-iSOCRestRequest -Method GET -Path (Get-iSOCResourcePath -Context $Context -ContentType $ContentType) -ApiVersion (Get-iSOCApiVersion $ContentType.ApiVersion))
    Write-iSOCLog "Found $($rules.Count) deployed Analytics Rules."
    $rules
}

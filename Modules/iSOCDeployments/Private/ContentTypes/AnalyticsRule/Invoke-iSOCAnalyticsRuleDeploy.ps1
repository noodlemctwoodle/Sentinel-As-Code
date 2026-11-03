#Requires -Version 7.2

<#
.SYNOPSIS
    Deploy handler for analytics rules: send a rule, retrying it disabled
    when the service will not validate its query.

.DESCRIPTION
    Copied from the send and retry in Deploy-CustomDetections
    (Deploy/content/Deploy-CustomContent.ps1), unchanged in behaviour.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/AnalyticsRule/Invoke-iSOCAnalyticsRuleDeploy.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.0
    Last Updated: 2026-11-03
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Invoke-iSOCAnalyticsRuleDeploy {
    <#
    .SYNOPSIS
        Send one analytics rule and say how it went.

    .DESCRIPTION
        - A Community rule is always sent disabled, and a rule with a
          missing dependency (-Disabled) too.
        - When the service rejects an enabled rule's query (a column it
          cannot resolve yet, such as a watchlist column not indexed yet),
          the rule is sent again disabled, so it exists and can be enabled
          later.
        - A rule that fails even though it was sent disabled for a missing
          dependency is skipped, not failed, as it was.
        - Any other failure throws, and deploy reports the rule failed.

    .PARAMETER Run
        The deployment run.

    .PARAMETER ContentType
        The analytics rule content type.

    .PARAMETER Item
        A repository item that passed Test-iSOCAnalyticsRule.

    .PARAMETER Disabled
        Send the rule disabled because a dependency is missing.

    .OUTPUTS
        [hashtable] Outcome (Deployed, DeployedDisabled, WhatIf or Skipped)
        and Reason.

    .EXAMPLE
        Invoke-iSOCAnalyticsRuleDeploy -Run $run -ContentType $rules -Item $item
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Run,

        [Parameter(Mandatory)]
        [psobject] $ContentType,

        [Parameter(Mandatory)]
        [psobject] $Item,

        [switch] $Disabled
    )

    if ($Item.Source -eq 'Community') { Write-iSOCLog '  Community rule; deploying as disabled' }
    $request = ConvertTo-iSOCAnalyticsRuleRequest -Item $Item -Disabled:$Disabled
    $enabled = [bool]$request.Body.properties.enabled

    if (-not $PSCmdlet.ShouldProcess($Item.RelativePath, "Deploy analytics rule '$($Item.Name)'")) {
        return @{ Outcome = 'WhatIf'; Reason = '' }
    }

    try {
        Send-iSOCContentRequest -Context $Run.Context -ContentType $ContentType -Request $request | Out-Null
        if ($Disabled) { return @{ Outcome = 'DeployedDisabled'; Reason = 'missing dependencies' } }
        if ($Item.Source -eq 'Community') { return @{ Outcome = 'DeployedDisabled'; Reason = 'Community rule' } }
        return @{ Outcome = 'Deployed'; Reason = '' }
    }
    catch {
        $errorMsg = $_.Exception.Message
        $isKqlError = $errorMsg -match 'FailedToResolveColumn|FailedToResolveScalarExpression|SemanticError|could not be found|Failed to run the analytics rule query'

        if ($Disabled) {
            Write-iSOCLog "Cannot deploy '$($Item.RelativePath)' even as disabled: $errorMsg" -Level Warning
            return @{ Outcome = 'Skipped'; Reason = "could not deploy even disabled: $errorMsg" }
        }
        if (-not ($isKqlError -and $enabled)) { throw }

        Write-iSOCLog "KQL validation error for '$($Item.RelativePath)'; retrying as disabled..." -Level Warning
        $retry = ConvertTo-iSOCAnalyticsRuleRequest -Item $Item -Disabled
        Send-iSOCContentRequest -Context $Run.Context -ContentType $ContentType -Request $retry | Out-Null
        return @{ Outcome = 'DeployedDisabled'; Reason = 'KQL validation' }
    }
}

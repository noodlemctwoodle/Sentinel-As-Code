#Requires -Version 7.6

<#
.SYNOPSIS
    Deploy the analytics rules the requested Content Hub solutions ship.

.DESCRIPTION
    Copied from Deploy-AnalyticsRules and Get-ExistingAnalyticsRules
    (Deploy/content/Deploy-SentinelContentHub.ps1). The wait for templates
    to propagate happens only after a solution was installed or updated in
    the run, and under -WhatIf nothing is written (MIGRATION.md edit E19).

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentHub/Invoke-iSOCContentHubRuleDeploy.ps1
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

function Invoke-iSOCContentHubRuleDeploy {
    <#
    .SYNOPSIS
        Create or update a rule from each of the solutions' rule templates,
        and return one result per template.

    .DESCRIPTION
        Reads the analytics rule templates and the workspace's rules, then
        for each template of a requested solution:
        - a template with no rule in it is skipped, one marked [Deprecated]
          left out, and one whose severity is not asked for skipped;
        - Get-iSOCContentHubRuleAction decides: an unchanged rule only has
          its solution metadata written, and a protected one is left alone
          with a warning;
        - the rule is sent with the preview alert rules API, the one that
          keeps sub-techniques, then linked to its solution. An NRT rule
          being updated is deleted and created again under a new name, as
          the service routes a PUT through the api-version the rule was
          made with, which may not know NRT;
        - a refusal the workspace can fix (a missing table or column, an
          expression the service cannot resolve, a template or bad request
          error) skips the rule with a warning; anything else fails it.
        When the templates cannot be read the step logs an error and
        returns nothing, as the script did.

    .PARAMETER Context
        The workspace context.

    .PARAMETER SolutionNames
        The solutions whose rules to deploy.

    .PARAMETER AvailableSolutions
        The catalogue, from Get-iSOCContentHubCatalogue.

    .PARAMETER Severity
        The severities to deploy.

    .PARAMETER NewSolutions
        The solutions installed or updated in this run, whose rules are
        all processed.

    .PARAMETER DisableRules
        Send rules disabled, and disable enabled ones.

    .PARAMETER ForceContentDeployment
        Redeploy rules that are current.

    .PARAMETER ProtectCustomisedRules
        Leave rules changed in the workspace alone.

    .PARAMETER PropagationSeconds
        Seconds to wait before reading the templates; 0 for none.

    .PARAMETER Metadata
        Counters, Linked and Failed, added to as rules are linked.

    .OUTPUTS
        [pscustomobject] iSOCDeployments.ContentHubResult, one per template.

    .EXAMPLE
        $results = @(Invoke-iSOCContentHubRuleDeploy -Context $ctx -SolutionNames $names -AvailableSolutions $hub.Available -Metadata $counters)
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Metadata', Justification = 'Read inside the link script block, which the analyser does not follow.')]
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Context,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $SolutionNames,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $AvailableSolutions,

        [string[]] $Severity = @('High', 'Medium', 'Low', 'Informational'),

        [AllowEmptyCollection()]
        [string[]] $NewSolutions = @(),

        [switch] $DisableRules,

        [switch] $ForceContentDeployment,

        [bool] $ProtectCustomisedRules = $true,

        [int] $PropagationSeconds = 0,

        [Parameter(Mandatory)]
        [hashtable] $Metadata
    )

    Write-iSOCLog 'Deploying Analytics Rules...' -Level Section
    if ($PropagationSeconds -gt 0) {
        Write-iSOCLog "Waiting for solution content templates to propagate (${PropagationSeconds}s)..."
        Start-Sleep -Seconds $PropagationSeconds
    }

    try {
        $allTemplates = @(Get-iSOCContentHubTemplate -Context $Context -Kind AnalyticsRule -ExpandMainTemplate)
        Write-iSOCLog "Found $($allTemplates.Count) Analytics Rule templates."
    }
    catch {
        Write-iSOCLog "Failed to fetch Analytics Rule templates: $($_.Exception.Message)" -Level Error
        return
    }

    $lookup = Get-iSOCContentHubSolutionLookup -SolutionNames $SolutionNames -AvailableSolutions $AvailableSolutions
    Write-iSOCLog "Solution detail lookup: $($lookup.Detail.Count) entries for metadata linking."

    $targetTemplates = @($allTemplates | Where-Object { ($_.properties.PSObject.Properties.Name -contains 'packageId') -and $lookup.ById.ContainsKey($_.properties.packageId) })
    Write-iSOCLog "Found $($targetTemplates.Count) Analytics Rule templates for target solutions."
    if ($targetTemplates.Count -eq 0) {
        Write-iSOCLog 'No Analytics Rule templates found for the specified solutions.' -Level Warning
        return
    }

    $workspace = $Context.WorkspaceResourceId
    $ruleApi = Get-iSOCApiVersion SecurityInsightsPreview
    Write-iSOCLog 'Fetching existing Analytics Rules...'
    $existingRules = @(Invoke-iSOCRestRequest -Method GET -Path "$workspace/providers/Microsoft.SecurityInsights/alertRules" -ApiVersion $ruleApi)
    Write-iSOCLog "Found $($existingRules.Count) existing Analytics Rules."

    $rulesByTemplate = @{}
    $rulesByName = @{}
    foreach ($rule in $existingRules) {
        if (($rule.properties.PSObject.Properties.Name -contains 'alertRuleTemplateName') -and $rule.properties.alertRuleTemplateName) {
            $rulesByTemplate[$rule.properties.alertRuleTemplateName] = $rule
        }
        if (($rule.properties.PSObject.Properties.Name -contains 'displayName') -and $rule.properties.displayName) {
            $rulesByName[$rule.properties.displayName] = $rule
        }
    }

    $link = {
        param($Record, [string] $RuleId, [string] $RuleName)
        $state = Set-iSOCContentHubRuleMetadata -Context $Context -Template $Record.Template -RuleId $RuleId -RuleName $RuleName `
            -TemplateName $Record.TemplateName -TemplateVersion $Record.TemplateVersion -Lookup $lookup -DisplayName $Record.DisplayName
        if ($state -eq 'Linked') { $Metadata.Linked++ }
        elseif ($state -eq 'Failed') { $Metadata.Failed++ }
    }

    foreach ($template in $targetTemplates) {
        $record = Read-iSOCContentHubRuleTemplate -Template $template
        $solution = if ($record.PackageId -and $lookup.ById.ContainsKey($record.PackageId)) { $lookup.ById[$record.PackageId] } else { $null }
        $name = if ($record.DisplayName) { $record.DisplayName } else { $record.Name }
        $emit = {
            param([string] $Outcome, [string] $Reason)
            New-iSOCContentHubResult -ContentType AnalyticsRule -Name $name -Identity $record.TemplateName -Solution $solution -Outcome $Outcome -Reason $Reason
        }

        if ($record.Problem) {
            if ($record.Problem -eq 'the template has no resources') { Write-iSOCLog "  Skipping template with no resources: $($record.Name)" -Level Debug }
            & $emit Skipped $record.Problem
            continue
        }
        $displayName = $record.DisplayName
        $ruleSeverity = $record.Severity
        if ($displayName -and $displayName -match '\[Deprecated\]') {
            Write-iSOCLog "  Skipping deprecated rule: $displayName" -Level Debug
            & $emit Deprecated 'the template is deprecated'
            continue
        }
        if ($Severity -and $ruleSeverity -and $Severity -notcontains $ruleSeverity) {
            & $emit Skipped "severity $ruleSeverity is not included"
            continue
        }

        $fromNew = [bool]($solution -and $NewSolutions -contains $solution)
        $decision = Get-iSOCContentHubRuleAction -Record $record -RulesByTemplate $rulesByTemplate -RulesByName $rulesByName -FromNewSolution:$fromNew `
            -DisableRules:$DisableRules -ForceContentDeployment:$ForceContentDeployment -ProtectCustomisedRules $ProtectCustomisedRules
        if ($decision.Action -eq 'Unchanged') {
            & $link $record $decision.ExistingRule.id $decision.ExistingRule.name
            & $emit Unchanged 'current'
            continue
        }
        if ($decision.Action -eq 'Protected') {
            if (@($decision.Modifications).Count -gt 0) {
                Write-iSOCLog "  CUSTOMISED RULE DETECTED: $displayName - Modified fields: $($decision.Modifications -join ', ') - Skipping update." -Level Warning
            }
            else {
                Write-iSOCLog "  CUSTOMISED RULE DETECTED (name match, no template link): $displayName - Skipping update." -Level Warning
            }
            & $emit Protected $decision.Reason
            continue
        }

        $needsUpdate = $decision.Action -eq 'Update'
        $existingRule = $decision.ExistingRule
        $verb = if ($needsUpdate) { 'update' } else { 'deploy' }
        if (-not $PSCmdlet.ShouldProcess($name, "$(if ($needsUpdate) { 'Update' } else { 'Create' }) Content Hub analytics rule")) {
            Write-iSOCLog "  [WhatIf] Would $verb rule: $displayName ($ruleSeverity)"
            & $emit WhatIf $verb
            continue
        }

        $body = ConvertTo-iSOCContentHubRuleRequest -Record $record -DisableRules:$DisableRules
        $kind = $record.Kind
        if ($kind -eq 'NRT' -and $needsUpdate -and $existingRule) {
            try {
                Invoke-iSOCRestRequest -Method DELETE -Path "$workspace/providers/Microsoft.SecurityInsights/alertRules/$($existingRule.name)" -ApiVersion $ruleApi | Out-Null
            }
            catch {
                Write-iSOCLog "  Warning: Could not delete existing NRT rule $displayName for recreation: $($_.Exception.Message)" -Level Warning
            }
            $existingRule = $null
            $needsUpdate = $false
        }

        $ruleId = if ($needsUpdate -and $existingRule) { $existingRule.name } else { (New-Guid).Guid }
        $rulePath = "$workspace/providers/Microsoft.SecurityInsights/alertRules/$ruleId"
        try {
            $ruleResult = Invoke-iSOCRestRequest -Method PUT -Path $rulePath -ApiVersion $ruleApi -Body $body
            if ($needsUpdate) {
                Write-iSOCLog "  Updated rule: $displayName ($ruleSeverity)" -Level Success
                & $emit Updated ''
            }
            else {
                Write-iSOCLog "  Deployed rule: $displayName ($ruleSeverity)" -Level Success
                & $emit Deployed ''
            }
            $resultId = Get-iSOCPropertyValue -InputObject $ruleResult -Path 'id'
            $resultName = Get-iSOCPropertyValue -InputObject $ruleResult -Path 'name'
            & $link $record $(if ($resultId) { $resultId } else { $rulePath }) $(if ($resultName) { $resultName } else { $ruleId })
            Start-Sleep -Milliseconds 500
        }
        catch {
            # Classified on the status and the service's message, without the
            # rule's path, which the REST client's error names and the
            # script's did not: a new rule's GUID can contain 400.
            $message = $_.Exception.Message -replace '^HTTP (\d+) from \S+ \S+: ', 'HTTP $1 - '
            $combinedError = "$message $(if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $_.ErrorDetails.Message })"
            $skip = switch -Regex ($combinedError) {
                'One of the tables does not exist' { 'missing tables in the environment'; break }
                'The given column' { 'missing column in the query'; break }
                'FailedToResolveScalarExpression|SemanticError' { 'invalid expression in the query'; break }
                'InvalidTemplate|DeploymentFailed' { 'template validation error'; break }
                'BadRequest|400' { 'bad request'; break }
            }
            if ($skip -eq 'bad request') {
                $nrtHint = if ($kind -eq 'NRT') { ' NRT rules must not include queryFrequency/queryPeriod.' } else { '' }
                $detail = $combinedError.Substring(0, [Math]::Min(300, $combinedError.Length))
                Write-iSOCLog "  Skipping $displayName ($kind) - bad request.$nrtHint Detail: $detail" -Level Warning
                & $emit Skipped "bad request: $detail"
            }
            elseif ($skip) {
                Write-iSOCLog "  Skipping $displayName - $skip." -Level Warning
                & $emit Skipped $skip
            }
            else {
                Write-iSOCLog "  Failed to deploy rule: $displayName - $combinedError" -Level Error
                & $emit Failed $combinedError.Trim()
            }
        }
    }
}

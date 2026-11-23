#Requires -Version 7.6

<#
.SYNOPSIS
    Write the dependency fixture's analytics rules, retrying while their queries cannot resolve yet.

.DESCRIPTION
    Rules go last: Sentinel validates a rule's query on write, so a 400 that
    cannot resolve a name is retried for a while.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/Rehearsal/New-iSOCFixtureRule.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function New-iSOCFixtureRule {
    <#
    .SYNOPSIS
        Write the dependency fixture's analytics rules, retrying while their
        queries cannot resolve yet.

    .DESCRIPTION
        Rules go last: Sentinel validates a rule's query against the
        workspace on write, so every table and parser in its chain must
        resolve. A write refused because a name cannot be resolved ('Failed
        to resolve' or 'SemanticError') is a propagation race, retried every
        30 seconds for up to the smaller of -TimeoutSeconds and ten minutes;
        any other refusal is a failure at once. Each rule asks ShouldProcess,
        and carries a description with the ownership sentinel.

    .PARAMETER Fixture
        From Get-iSOCDependencyFixturePlan.

    .PARAMETER RunId
        The run.

    .PARAMETER Enabled
        Make the rules enabled.

    .PARAMETER TimeoutSeconds
        The run's wait budget.

    .OUTPUTS
        [pscustomobject] Created and Failed.

    .EXAMPLE
        New-iSOCFixtureRule -Fixture $fixture -RunId $runId -TimeoutSeconds 900
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Fixture,

        [Parameter(Mandatory)]
        [string] $RunId,

        [switch] $Enabled,

        [Parameter(Mandatory)]
        [int] $TimeoutSeconds
    )

    $marker = (Get-iSOCDependencyFixtureSetting).FixtureMarker
    $created = [System.Collections.Generic.List[string]]::new()
    $failed = [System.Collections.Generic.List[string]]::new()
    $ruleEnabled = [bool]$Enabled

    Write-iSOCLog 'Creating analytics rules' -Level Section
    Write-iSOCLog 'Rules go last. Sentinel validates a rule query against the workspace schema on write, so every table and every parser in the chain has to resolve first.'
    foreach ($rule in $Fixture.Plan.Rule) {
        $resource = "$($Fixture.SentinelBase)/alertRules/$($rule.RuleId)"
        $action = if ($ruleEnabled) { 'Create ENABLED fixture analytics rule' } else { 'Create DISABLED fixture analytics rule' }
        if (-not $PSCmdlet.ShouldProcess($resource, $action)) {
            Write-iSOCLog "Skipped rule $($rule.DisplayName)." -Level Warning
            continue
        }

        $description = New-iSOCFixtureDescription -NamePrefix $Fixture.Plan.NamePrefix -FixtureMarker $marker -RunId $RunId -ScenarioName $rule.ScenarioName -Enabled $ruleEnabled
        $body = New-iSOCFixtureAlertRuleBody -DisplayName $rule.DisplayName -Description $description -Query $rule.Query -Enabled $ruleEnabled
        $attemptDeadline = [datetime]::UtcNow.AddSeconds([math]::Min($TimeoutSeconds, 600))
        $written = $false
        $lastError = $null
        while (-not $written) {
            try {
                Invoke-iSOCRestRequest -Method PUT -Path $resource -ApiVersion (Get-iSOCApiVersion SecurityInsights) -Body $body | Out-Null
                $written = $true
            } catch {
                $lastError = $_.Exception.Message
                $isResolveRace = ($lastError -match 'Failed to resolve') -or ($lastError -match 'SemanticError')
                if ($isResolveRace -and [datetime]::UtcNow -lt $attemptDeadline) {
                    Write-iSOCLog "Rule '$($rule.DisplayName)' cannot resolve its query yet. Retrying in 30s."
                    Start-Sleep -Seconds 30
                    continue
                }
                break
            }
        }

        if ($written) {
            $state = if ($ruleEnabled) { 'enabled' } else { 'disabled' }
            Write-iSOCLog "Created $state rule '$($rule.DisplayName)' ($($rule.RuleId))." -Level Success
            $created.Add($resource)
        } else {
            Write-iSOCLog "Failed to create rule '$($rule.DisplayName)': $($lastError.Split([char]10)[0])" -Level Warning
            $failed.Add($resource)
        }
    }
    [pscustomobject]@{ Created = $created.ToArray(); Failed = $failed.ToArray() }
}

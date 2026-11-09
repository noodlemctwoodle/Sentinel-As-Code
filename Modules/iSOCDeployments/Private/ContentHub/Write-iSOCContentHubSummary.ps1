#Requires -Version 7.6

<#
.SYNOPSIS
    Log a Content Hub run's totals and return its result.

.DESCRIPTION
    Replaces the summary at the end of Invoke-Main
    (Deploy/content/Deploy-SentinelContentHub.ps1). The run returns
    ExitCode instead of exiting, and the Azure DevOps variables
    SentinelDeploymentFailed and SentinelCustomisedRulesSkipped, which
    nothing read, are no longer set (MIGRATION.md edit E19).

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentHub/Write-iSOCContentHubSummary.ps1
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

function Write-iSOCContentHubSummary {
    <#
    .SYNOPSIS
        Log the counts per kind and build the run result.

    .PARAMETER Results
        Every iSOCDeployments.ContentHubResult of the run.

    .PARAMETER Metadata
        The Linked and Failed metadata counters.

    .PARAMETER AutomationRuleTemplates
        The solutions' automation rule templates.

    .PARAMETER HuntingQueryTemplates
        The solutions' hunting query templates.

    .PARAMETER Started
        When the run started.

    .OUTPUTS
        [pscustomobject] iSOCDeployments.ContentHubRun: Solutions (the
        solution results), Results (every result), Deployed, Updated,
        Unchanged, Protected, Skipped, Failed and WhatIf (counts over every
        result; Skipped includes deprecated templates), MetadataLinked,
        MetadataFailed, AutomationRuleTemplates, HuntingQueryTemplates,
        Duration and ExitCode (1 when anything failed, else 0).

    .EXAMPLE
        Write-iSOCContentHubSummary -Results $results -Metadata $metadata -AutomationRuleTemplates 2 -HuntingQueryTemplates 5 -Started $start
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Results,

        [Parameter(Mandatory)]
        [hashtable] $Metadata,

        [int] $AutomationRuleTemplates,

        [int] $HuntingQueryTemplates,

        [Parameter(Mandatory)]
        [datetime] $Started
    )

    $count = {
        param($Items, [string[]] $Outcomes)
        @($Items | Where-Object { $_.Outcome -in $Outcomes }).Count
    }
    $duration = (Get-Date) - $Started

    Write-iSOCLog ''
    Write-iSOCLog ('=' * 64) -Level Section
    Write-iSOCLog '  Deployment Summary' -Level Section
    Write-iSOCLog ('=' * 64) -Level Section
    foreach ($kind in @(@{ Type = 'Solution'; Label = 'Solutions' }, @{ Type = 'AnalyticsRule'; Label = 'Analytics Rules' }, @{ Type = 'Workbook'; Label = 'Workbooks' })) {
        $items = @($Results | Where-Object { $_.ContentType -eq $kind.Type })
        $whatIf = & $count $items 'WhatIf'
        $would = if ($whatIf -gt 0) { "  Would deploy: $whatIf" } else { '' }
        Write-iSOCLog ''
        Write-iSOCLog "  $($kind.Label):"
        Write-iSOCLog "    Deployed: $(& $count $items 'Deployed')  Updated: $(& $count $items 'Updated')  Unchanged: $(& $count $items 'Unchanged')  Skipped: $(& $count $items 'Skipped', 'Deprecated')  Failed: $(& $count $items 'Failed')$would"
        $protected = & $count $items 'Protected'
        if ($protected -gt 0) { Write-iSOCLog "    Customised rules protected: $protected" -Level Warning }
    }
    Write-iSOCLog ''
    Write-iSOCLog '  Automation Rules:'
    Write-iSOCLog "    Available from the solutions: $AutomationRuleTemplates"
    Write-iSOCLog ''
    Write-iSOCLog '  Hunting Queries:'
    Write-iSOCLog "    Available from the solutions: $HuntingQueryTemplates"
    Write-iSOCLog ''
    Write-iSOCLog '  Metadata:'
    Write-iSOCLog "    Linked: $($Metadata.Linked)  Failed: $($Metadata.Failed)"
    Write-iSOCLog ''
    Write-iSOCLog "  Duration: $($duration.ToString('hh\:mm\:ss'))"
    Write-iSOCLog ('=' * 64) -Level Section

    $failed = & $count $Results 'Failed'
    if ($failed -gt 0) { Write-iSOCLog "Deployment completed with $failed failure(s)." -Level Error }
    else { Write-iSOCLog 'Deployment completed successfully.' -Level Success }

    [pscustomobject]@{
        PSTypeName              = 'iSOCDeployments.ContentHubRun'
        Solutions               = @($Results | Where-Object { $_.ContentType -eq 'Solution' })
        Results                 = @($Results)
        Deployed                = & $count $Results 'Deployed'
        Updated                 = & $count $Results 'Updated'
        Unchanged               = & $count $Results 'Unchanged'
        Protected               = & $count $Results 'Protected'
        Skipped                 = & $count $Results 'Skipped', 'Deprecated'
        Failed                  = $failed
        WhatIf                  = & $count $Results 'WhatIf'
        MetadataLinked          = [int]$Metadata.Linked
        MetadataFailed          = [int]$Metadata.Failed
        AutomationRuleTemplates = $AutomationRuleTemplates
        HuntingQueryTemplates   = $HuntingQueryTemplates
        Duration                = $duration
        ExitCode                = if ($failed -gt 0) { 1 } else { 0 }
    }
}

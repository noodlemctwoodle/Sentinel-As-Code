#Requires -Version 7.6

<#
.SYNOPSIS
    Stage 6: bring the findings list in line with the bundle.

.DESCRIPTION
    A step of the SharePoint site publish. Steps run in order and pass their results
    to later ones through the publish context.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Publish/Steps/Invoke-PublishFinding.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-16
    Component:    iSOC Blueprint, SharePoint site publisher
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Invoke-PublishFinding {
    <#
    .SYNOPSIS
        Stage 6: bring the findings list in line with the bundle.

    .PARAMETER Context
        The publish context: the values earlier steps produced and this one adds to.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Reports the finding plan to the operator at the console as the publish runs.')]
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the publish context.
    $findingsDoc = $Context.findingsDoc

    # 6. Findings ----------------------------------------------------------------
    Write-PublishStep '6/8 Findings list'
    Assert-TokenFresh 'findings'
    $checks = if ($null -ne $findingsDoc.checks) {
        @($findingsDoc.checks | ForEach-Object { [pscustomobject]@{ Id = $_.id; Outcome = $_.outcome } })
    } else { $null }
    $findingPlan = Get-FindingSyncPlan -Current @($findingsDoc.items) -Existing (Get-SacFindingItem) `
        -Checks $checks -AnalysisAvailable ([bool]$findingsDoc.analysisAvailable) -NowUtc (Get-Date).ToUniversalTime()
    Write-Host "  Plan: $(if ($findingPlan.Count) { ($findingPlan | Group-Object Action | ForEach-Object { "$($_.Count) $($_.Name)" }) -join ', ' } else { 'no changes' })"
    Invoke-SacFindingPlan -Plan $findingPlan
}

#Requires -Version 7.6

<#
.SYNOPSIS
    Close the run: stamp run-context.json and print the capture summary.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Setup/Complete-CollectorRun.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Collector
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Complete-CollectorRun {
    <#
    .SYNOPSIS
        Write the finished run-context.json and the capture summary.

    .PARAMETER RunContext
        The record from New-CollectorRunContext.

    .PARAMETER RawOut
        The _raw folder the run wrote.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] $RunContext,
        [Parameter(Mandatory = $true)] [string]$RawOut
    )

    $rawOut = $RawOut
    $runContext = $RunContext | Add-Member -MemberType NoteProperty -Name CompletedAtUtc -Value (Get-Date).ToUniversalTime().ToString('o') -PassThru
    # The captures that failed, each marked Permission or Error, for the run
    # summary New-iSOCBlueprint prints at the end.
    $runContext | Add-Member -MemberType NoteProperty -Name CaptureIssues -Value @($script:CaptureErrors) -Force
    Save-Json -FileName 'run-context.json' -Data $runContext

    # Diagnostic pass, sanity-check captures that typically contain data on
    # any active workspace. Empty results here are NOT necessarily a bug
    # (some files legitimately empty on quiet workspaces), but they almost
    # always indicate either an RBAC gap, an unsupported region, or an
    # undocumented schema change, and they're the single most common
    # source of "the renderer says zero of X but I have a hundred"
    # regressions. Surface them prominently in the run log so the operator
    # notices before opening a bug.
    $expectNonEmpty = @(
        'alert-rules.json',
        'data-connectors-classic.json',
        'workspace.json',
        'workspace-tables.json',
        'rule-table-references.json'
    )
    $expectIfActive = @(
        'automation-rules.json',
        'watchlists.json',
        'playbooks.json',
        'hunting-queries.json',
        'workbooks-saved.json',
        'cost-estimate.json',
        'rule-effectiveness.json',
        'rules-fired.json',
        'incident-title-stats.json',
        'playbook-runs.json',
        'workspace-usage-daily.json'
    )

    Write-CaptureSummary -RawRoot $rawOut -Issues @($script:CaptureErrors) -ExpectNonEmpty $expectNonEmpty -ExpectIfActive $expectIfActive
}

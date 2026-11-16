#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'playbook-runs': writes playbook-runs.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Playbooks/Invoke-PlaybookRunsCapture.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-16
    Component:    iSOC Blueprint, Collector
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function Invoke-PlaybookRunsCapture {
    <#
    .SYNOPSIS
        Capture 'playbook-runs': writes playbook-runs.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)


    # Run health per playbook over the lookback, one bounded call per
    # enabled workflow. Disabled workflows get a zero row without a call. A
    # failure on one workflow is logged and the others are still recorded.
    $since = (Get-Date).ToUniversalTime().AddDays(-$script:LookbackDays).ToString('yyyy-MM-ddTHH:mm:ssZ')
    $runRows = @()
    $runsTried = 0
    $runFailures = @()
    foreach ($wf in $script:Workflows) {
        if ($null -eq $wf) { continue }
        $wfName = [string]$wf.name
        $state = ''
        if ($wf.PSObject.Properties.Name -contains 'properties' -and $null -ne $wf.properties -and
            $wf.properties.PSObject.Properties.Name -contains 'state') { $state = [string]$wf.properties.state }
        $row = [ordered]@{
            Playbook = $wfName
            Id = [string]$wf.id
            Runs7d = 0
            Failed7d = 0
            LastFailureUtc = $null
            LastRunStatus = $null
            Note = $null
            Daily = @()
        }
        if ($state -eq 'Enabled') {
            $runsTried++
            try {
                $runs = @(Invoke-SentinelRest -Path "$($wf.id)/runs?`$top=250&`$filter=startTime ge $since" -ApiVersion '2016-06-01')
                $runs = @($runs | Where-Object { $null -ne $_ -and $_.PSObject.Properties.Name -contains 'properties' })
                $failed = @($runs | Where-Object { [string]$_.properties.status -in @('Failed', 'TimedOut', 'Aborted') })
                $row.Runs7d = $runs.Count
                $row.Failed7d = $failed.Count
                # Runs and failures per day for the dashboard's slider, as
                # days ago (0 = the last 24 hours), within the daily span.
                $nowUtc = (Get-Date).ToUniversalTime()
                $byDay = @{}
                foreach ($run in $runs) {
                    $ago = [int][math]::Floor(($nowUtc - ([datetime]$run.properties.startTime).ToUniversalTime()).TotalDays)
                    if ($ago -lt 0 -or $ago -ge $script:DailyDays) { continue }
                    if (-not $byDay.ContainsKey($ago)) { $byDay[$ago] = [ordered]@{ DaysAgo = $ago; Runs = 0; Failed = 0 } }
                    $byDay[$ago].Runs++
                    if ([string]$run.properties.status -in @('Failed', 'TimedOut', 'Aborted')) { $byDay[$ago].Failed++ }
                }
                $row.Daily = @($byDay.Keys | Sort-Object | ForEach-Object { [pscustomobject]$byDay[$_] })
                if ($runs.Count -gt 0) {
                    $latest = $runs | Sort-Object { [datetime]$_.properties.startTime } -Descending | Select-Object -First 1
                    $row.LastRunStatus = [string]$latest.properties.status
                }
                if ($failed.Count -gt 0) {
                    $lastFailed = $failed | Sort-Object { [datetime]$_.properties.startTime } -Descending | Select-Object -First 1
                    $row.LastFailureUtc = [string]$lastFailed.properties.startTime
                }
            } catch {
                # Marked so consumers can tell "no runs" from "could not read".
                $row.LastRunStatus = 'Unavailable'
                $row.Note = "Run history not readable: $($_.Exception.Message)"
                $runFailures += [pscustomobject]@{ Name = $wfName; Message = $_.Exception.Message }
            }
        }
        $runRows += [pscustomobject]$row
    }
    # One line for the playbooks whose history could not be read, not one each.
    foreach ($issue in @(
        Write-PartialCaptureIssue -Label 'playbook-runs' -What 'the run history of' -Noun 'playbook', 'playbooks' -Total $runsTried -Failures $runFailures
    )) {
        $script:CaptureErrors.Add($issue)
    }
    Save-Json -FileName 'playbook-runs.json' -Data $runRows
}

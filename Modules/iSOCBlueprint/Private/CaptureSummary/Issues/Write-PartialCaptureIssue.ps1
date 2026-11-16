#Requires -Version 7.6

<#
.SYNOPSIS
    One line for a capture that could not read some of its items, in place of a line an item, and the issues for the run summary.

.NOTES
    File:         Modules/iSOCBlueprint/Private/CaptureSummary/Issues/Write-PartialCaptureIssue.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.1.0
    Last Updated: 2026-11-16
    Component:    iSOC Blueprint, Capture reporting
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function Write-PartialCaptureIssue {
    <#
    .SYNOPSIS
        One line for a capture that could not read some of its items, in
        place of a line an item, and the issues for the run summary.

    .DESCRIPTION
        Each outcome gets its own line: "no permission: the run history of
        3 of 12 playbooks (401 Unauthorized): A, B, C."

    .PARAMETER Label
        The capture's label.

    .PARAMETER What
        What could not be read, ending in "of": 'the run history of'.

    .PARAMETER Noun
        The item, singular and plural: 'playbook', 'playbooks'.

    .PARAMETER Total
        How many items the capture tried to read.

    .PARAMETER Failures
        Name and Message for each item that could not be read.

    .OUTPUTS
        [pscustomobject] Label, Kind and Message, one for each outcome, for
        the run's issue list.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Label,
        [Parameter(Mandatory)] [string] $What,
        [Parameter(Mandatory)] [string[]] $Noun,
        [int] $Total,
        [object[]] $Failures = @()
    )

    $items = if ($Total -eq 1) { $Noun[0] } else { $Noun[-1] }
    foreach ($group in @($Failures | Where-Object { $_ } | Group-Object -Property { Get-CaptureIssueKind $_.Message } | Sort-Object Name -Descending)) {
        $names = @($group.Group | ForEach-Object { [string]$_.Name } | Sort-Object -Unique)
        $statuses = @($group.Group | ForEach-Object { Get-CaptureStatusText $_.Message } | Where-Object { $_ } | Sort-Object -Unique)
        $status = if ($statuses.Count) { " ($($statuses -join ', '))" } else { '' }
        $text = "$What $($names.Count) of $Total $items${status}: $($names -join ', ')."
        if ($group.Name -eq 'Error') { $text = "could not read $text First error: $(Format-CaptureMessage ([string]$group.Group[0].Message))" }
        Write-CaptureNote -Kind $group.Name -Label $Label -Text $text
        # The summary lists it under its outcome, so it reads as a sentence.
        $sentence = switch ($group.Name) {
            'Permission'   { "No permission to read $text" }
            'NotAvailable' { "Not available: $text" }
            default        { 'C' + $text.Substring(1) }
        }
        [pscustomobject]@{ Label = $Label; Kind = $group.Name; Message = $sentence }
    }
}

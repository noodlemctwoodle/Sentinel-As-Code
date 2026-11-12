#Requires -Version 7.6

<#
.SYNOPSIS
    Run one capture, recording a failure instead of stopping the run.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Helpers/Try-Capture.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, Collector
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function Try-Capture {
    param(
        [Parameter(Mandatory)] [string]$Label,
        [Parameter(Mandatory)] [scriptblock]$Action
    )
    try {
        Write-Information "[$Label]"
        & $Action
    } catch {
        $msg = Get-CaptureErrorText $_
        # Surface the failure prominently. Try-Capture used to log only a
        # Write-Warning which is easy to miss in long ADO logs and silently
        # leaves the corresponding _raw/<file>.json absent or stale. We now
        # also accumulate the failure into a summary written at the end,
        # which lists what the workspace does not have and the refusals for
        # want of a role or permission (expected under an identity without
        # every role) apart from other errors. Each outcome has its own
        # colour as it happens; the summary carries the full message.
        $kind = Get-CaptureIssueKind $msg
        $status = Get-CaptureStatusText $msg
        switch ($kind) {
            'Permission'   { Write-CaptureNote -Kind Permission -Label $Label -Text "skipped$(if ($status) { " ($status)" }). The capture summary at the end says what it needs." }
            'NotAvailable' { Write-CaptureNote -Kind NotAvailable -Label $Label -Text "skipped. $(Format-CaptureMessage $msg)" }
            default        { Write-CaptureNote -Kind Error -Label $Label -Text $msg }
        }
        $script:CaptureErrors.Add([pscustomobject]@{
            Label   = $Label
            Kind    = $kind
            Message = $msg
        })
    }
}

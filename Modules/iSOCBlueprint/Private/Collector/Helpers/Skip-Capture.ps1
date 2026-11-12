#Requires -Version 7.6

<#
.SYNOPSIS
    Record a capture whose read failed and write its empty file.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Helpers/Skip-Capture.ps1
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

# For a capture whose read failed inside its own try/catch: the empty file
# it has always written (so consumers still read "captured, none"), and now
# a line saying why, in the outcome's colour, and an entry in the summary.
# The label is the file's name without .json.
function Skip-Capture {
    param(
        [Parameter(Mandatory)] [string]$FileName,
        $ErrorRecord,
        [string]$What
    )
    $label = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
    $msg = Get-CaptureErrorText $ErrorRecord
    $kind = Get-CaptureIssueKind $msg
    $text = Format-CaptureMessage $msg
    if ($What) { $text = "${What}: $text" }
    # Why first, then the empty file it leads to.
    Write-CaptureNote -Kind $kind -Label $label -Text $(if ($kind -eq 'Error') { $msg } else { $text })
    Save-Json -FileName $FileName -Data @()
    $script:CaptureErrors.Add([pscustomobject]@{ Label = $label; Kind = $kind; Message = $(if ($What) { "${What}: $msg" } else { $msg }) })
}

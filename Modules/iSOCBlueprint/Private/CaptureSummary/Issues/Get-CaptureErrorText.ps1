#Requires -Version 7.6

<#
.SYNOPSIS
    An error's message with the service's own reason added, which Invoke-
    AzOperationalInsightsQuery keeps out of the message ("Operation returned an invalid status
    code 'BadRequest'") and in the body.

.NOTES
    File:         Modules/iSOCBlueprint/Private/CaptureSummary/Issues/Get-CaptureErrorText.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.1.2
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Capture reporting
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-CaptureErrorText {
    <#
    .SYNOPSIS
        An error's message with the service's own reason added, which
        Invoke-AzOperationalInsightsQuery keeps out of the message ("Operation
        returned an invalid status code 'BadRequest'") and in the body.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowNull()] $ErrorRecord)

    if ($null -eq $ErrorRecord) { return '' }
    $ex = if ($ErrorRecord -is [System.Management.Automation.ErrorRecord]) { $ErrorRecord.Exception } else { $ErrorRecord }
    if ($ex -isnot [System.Exception]) { return [string]$ErrorRecord }
    $parts = [System.Collections.Generic.List[string]]::new()
    $parts.Add($ex.Message.Trim())
    $probes = @(
        { $ex.Body.Error.Message }
        { $ex.Body.Error.Innererror.Message }
        { $ex.Body.Error.Details | ForEach-Object { $_.Message } }
        { [regex]::Matches([string]$ex.Response.Content, '"message"\s*:\s*"((?:[^"\\]|\\.)*)"') | ForEach-Object { $_.Groups[1].Value -replace '\\"', '"' } }
    )
    foreach ($probe in $probes) {
        try {
            foreach ($value in @(& $probe)) {
                $text = ([string]$value).Trim()
                if ($text -and -not $parts.Contains($text) -and -not $parts[0].Contains($text)) { $parts.Add($text) }
            }
        } catch { }
    }
    ($parts | ForEach-Object { $_.TrimEnd('.') }) -join '. '
}

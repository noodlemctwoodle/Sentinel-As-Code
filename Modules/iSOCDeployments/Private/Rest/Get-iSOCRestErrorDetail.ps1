#Requires -Version 7.2

<#
.SYNOPSIS
    Read the reason a failed ARM or Graph request gave.

.NOTES
    File:         Modules/iSOCDeployments/Private/Rest/Get-iSOCRestErrorDetail.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-23
    Version:      0.1.0
    Last Updated: 2026-10-23
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCRestErrorDetail {
    <#
    .SYNOPSIS
        Turn an error response body into one line of text.

    .DESCRIPTION
        ARM and Graph both answer a failure with { "error": { "code",
        "message", "details": [...] } }. The code, the message and each
        detail's message are joined, so text callers look for (a KQL
        validation failure, say) is kept wherever the service put it. A body
        that is not that shape is returned trimmed, cut at 2000 characters.

    .PARAMETER Content
        The response body.

    .OUTPUTS
        [string]

    .EXAMPLE
        Get-iSOCRestErrorDetail -Content $response.Content
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyString()]
        [AllowNull()]
        [string] $Content
    )

    if ([string]::IsNullOrWhiteSpace($Content)) { return 'no response body' }

    $parsed = $null
    try { $parsed = $Content | ConvertFrom-Json -ErrorAction Stop } catch { $parsed = $null }

    if ($parsed -and $parsed.PSObject.Properties['error'] -and $parsed.error) {
        $err = $parsed.error
        $parts = [System.Collections.Generic.List[string]]::new()
        if ($err.PSObject.Properties['code'] -and $err.code) { $parts.Add([string]$err.code) }
        if ($err.PSObject.Properties['message'] -and $err.message) { $parts.Add([string]$err.message) }
        if ($err.PSObject.Properties['details'] -and $err.details) {
            foreach ($detail in @($err.details)) {
                if ($detail.PSObject.Properties['message'] -and $detail.message) { $parts.Add([string]$detail.message) }
            }
        }
        if ($parts.Count -gt 0) { return ($parts -join ': ') }
    }

    $text = $Content.Trim()
    if ($text.Length -gt 2000) { $text = $text.Substring(0, 2000) + '...' }
    $text
}

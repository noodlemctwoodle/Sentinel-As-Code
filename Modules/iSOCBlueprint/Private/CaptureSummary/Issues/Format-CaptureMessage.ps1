#Requires -Version 7.6

<#
.SYNOPSIS
    A capture's error message on one line, without the HTTP client's "Response status code does not indicate success" wording.

.NOTES
    File:         Modules/iSOCBlueprint/Private/CaptureSummary/Issues/Format-CaptureMessage.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.1.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Capture reporting
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Format-CaptureMessage {
    <#
    .SYNOPSIS
        A capture's error message on one line, without the HTTP client's
        "Response status code does not indicate success" wording.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowEmptyString()] [string] $Message)

    $text = ($Message -replace '\s+', ' ').Trim()
    $text = $text -replace 'Response status code does not indicate success: (\w+) \(\1\)\.?', '$1.'
    $text = $text -replace 'Response status code does not indicate success: (\d{3}) \(([^)]+)\)\.?', '$1 $2.'
    # "HTTP 400: {json}" from Invoke-SentinelRest: the service's code and message.
    if ($text -match '^HTTP (?<status>\d{3}): (?<body>\{.*\})$') {
        $status = $Matches['status']
        $body = $Matches['body']
        $code = if ($body -match '"code"\s*:\s*"(?<c>[^"]+)"') { " $($Matches['c'])" } else { '' }
        $said = if ($body -match '"message"\s*:\s*"(?<m>(?:[^"\\]|\\.)*)"') { ": $($Matches['m'] -replace '\\"', '"')" } else { '' }
        $text = "$status$code$said"
    }
    # An ARM URL shortened to its resource path after the last provider, so
    # the line stays short and carries no subscription or workspace ids.
    $text = [regex]::Replace($text, 'https?://management\.[a-z.]+(?<path>/[^\s?"]*)(\?[^\s"]*)?', [System.Text.RegularExpressions.MatchEvaluator] {
        param($m)
        $path = $m.Groups['path'].Value
        $i = $path.LastIndexOf('/providers/')
        if ($i -ge 0) { $path.Substring($i + 11) } else { $path }
    })
    # ARM appends every api-version and region it supports to some errors;
    # the reason is in the sentence before.
    $text = $text -replace "\s*The supported [A-Za-z -]+ are '[^']*'\.?", ''
    $text -replace '\.{2,}(?=\s|$)', '.'
}

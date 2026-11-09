#Requires -Version 7.6

<#
.SYNOPSIS
    How long to wait before retrying a throttled or failed request.

.NOTES
    File:         Modules/iSOCDeployments/Private/Rest/Get-iSOCRestRetryDelay.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-23
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCRestRetryDelay {
    <#
    .SYNOPSIS
        Seconds to wait, from Retry-After when the service sent one.

    .DESCRIPTION
        ARM and Graph send Retry-After with a 429 and with some 503s, as a
        number of seconds or a date. Without it the wait doubles from five
        seconds on each attempt. Either way it is at least one second and at
        most two minutes.

    .PARAMETER Headers
        The response headers: the HttpResponseHeaders Invoke-AzRestMethod
        returns, or a dictionary.

    .PARAMETER Attempt
        The attempt that just failed, from 1.

    .OUTPUTS
        [int] Seconds.

    .EXAMPLE
        Start-Sleep -Seconds (Get-iSOCRestRetryDelay -Headers $response.Headers -Attempt 2)
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [AllowNull()]
        [object] $Headers,

        [Parameter(Mandatory)]
        [ValidateRange(1, 100)]
        [int] $Attempt
    )

    $seconds = $null
    if ($Headers -is [System.Net.Http.Headers.HttpResponseHeaders]) {
        $retryAfter = $Headers.RetryAfter
        if ($retryAfter -and $null -ne $retryAfter.Delta) { $seconds = $retryAfter.Delta.TotalSeconds }
        elseif ($retryAfter -and $null -ne $retryAfter.Date) { $seconds = ($retryAfter.Date - [DateTimeOffset]::UtcNow).TotalSeconds }
    }
    elseif ($Headers -is [System.Collections.IDictionary]) {
        $value = $null
        foreach ($key in $Headers.Keys) {
            if ("$key" -ieq 'Retry-After') { $value = "$(@($Headers[$key])[0])" }
        }
        if ($value) {
            $number = 0
            $date = [DateTimeOffset]::MinValue
            if ([int]::TryParse($value, [ref]$number)) { $seconds = $number }
            elseif ([DateTimeOffset]::TryParse($value, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$date)) {
                $seconds = ($date - [DateTimeOffset]::UtcNow).TotalSeconds
            }
        }
    }

    if ($null -eq $seconds) { $seconds = 5 * [math]::Pow(2, $Attempt - 1) }
    [int][math]::Ceiling([math]::Min(120, [math]::Max(1, $seconds)))
}

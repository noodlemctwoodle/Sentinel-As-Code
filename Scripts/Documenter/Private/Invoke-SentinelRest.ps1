<#
.SYNOPSIS
    Paginating wrapper around Invoke-AzRestMethod for Sentinel and Azure Resource Manager
    REST endpoints.

.DESCRIPTION
    The Az.SecurityInsights cmdlets do not cover the full Sentinel REST surface — Codeless
    Connector Framework (CCF) connectors, Content Hub packages, summary rules, settings,
    pricings, sourceControls, and full DCR JSON all require direct REST calls. This helper
    centralises the call pattern so:

    - 'value[]' + 'nextLink' pagination is followed transparently and the caller receives
      the flattened collection.
    - 429 (Too Many Requests) and 5xx errors are retried with exponential backoff capped at
      five attempts.
    - 404 is treated as 'no resource' (returns @()) for endpoints where absence is the
      expected steady-state (settings/Ueba on a workspace where UEBA is off, etc.). Pass
      -ThrowOn404 to opt out.
    - The api-version is forced into the query string when the caller hasn't already
      embedded one — saves every caller from string-building.

    Read-only by design: only GET requests. The collector should never mutate the tenant.

.PARAMETER Path
    The resource path or full URL to call. If a path is given (starting with /) the
    Invoke-AzRestMethod default ARM endpoint is used. If a fully qualified URL is given
    it is passed through (used by the Retail Prices client).

.PARAMETER ApiVersion
    The api-version to embed in the query string when not already present.

.PARAMETER ThrowOn404
    Treat 404 as a hard error rather than the empty-collection signal.

.PARAMETER MaxAttempts
    Maximum retry attempts (default 5). Each retry waits 2^(attempt-1) seconds plus jitter.

.OUTPUTS
    [PSCustomObject[]] — the flattened 'value' collection, or for endpoints that return a
    single object, the object itself wrapped in a single-element array.

.EXAMPLE
    Invoke-SentinelRest -Path '/subscriptions/.../providers/Microsoft.SecurityInsights/dataConnectorDefinitions' -ApiVersion '2024-09-01'

.NOTES
    Author:         noodlemctwoodle
    Component:      Sentinel Documenter
    Last Updated:   2026-05-06
#>

function Invoke-SentinelRest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [string]$ApiVersion,

        [Parameter(Mandatory = $false)]
        [switch]$ThrowOn404,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 10)]
        [int]$MaxAttempts = 5
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    # Build initial URL — embed api-version if the caller hasn't already.
    $url = $Path
    if ($ApiVersion -and ($url -notmatch '[?&]api-version=')) {
        $separator = if ($url -match '\?') { '&' } else { '?' }
        $url = "$url$separator`api-version=$ApiVersion"
    }

    $accumulator = New-Object System.Collections.Generic.List[object]

    while ($url) {
        $attempt = 0
        $response = $null

        while ($true) {
            $attempt++

            try {
                if ($url -match '^https?://') {
                    # Absolute URL — used by the public Retail Prices API which is anonymous.
                    $response = Invoke-RestMethod -Uri $url -Method Get -ErrorAction Stop
                } else {
                    # ARM endpoint — Invoke-AzRestMethod uses the active context's audience.
                    $raw = Invoke-AzRestMethod -Path $url -Method GET -ErrorAction Stop
                    if ($raw.StatusCode -eq 404) {
                        if ($ThrowOn404) {
                            throw "404 Not Found: $url"
                        }
                        return @()
                    }
                    if ($raw.StatusCode -ge 400) {
                        throw [System.Net.WebException]::new(
                            "HTTP $($raw.StatusCode): $($raw.Content)"
                        )
                    }
                    $response = $raw.Content | ConvertFrom-Json -ErrorAction Stop
                }
                break
            }
            catch {
                $message = $_.Exception.Message
                $isRetryable = $message -match '\b(429|503|504|408)\b' -or
                               $message -match 'TooManyRequests' -or
                               $message -match 'timed? out'

                if ($attempt -ge $MaxAttempts -or -not $isRetryable) {
                    throw
                }

                $backoffSeconds = [math]::Pow(2, $attempt - 1)
                $jitter = Get-Random -Minimum 0.0 -Maximum 1.0
                $sleep = $backoffSeconds + $jitter
                Write-Verbose "Invoke-SentinelRest retry $attempt/$MaxAttempts after ${sleep}s: $message"
                Start-Sleep -Seconds $sleep
            }
        }

        # Flatten — most ARM endpoints return { value: [...], nextLink: '...' }; a few
        # return the single resource at the root, in which case 'value' is absent.
        if ($null -ne $response) {
            if ($response.PSObject.Properties.Name -contains 'value') {
                if ($response.value) {
                    foreach ($item in $response.value) { $accumulator.Add($item) }
                }
                # Public Retail Prices uses NextPageLink; ARM uses nextLink. Honour both.
                $next = $null
                if ($response.PSObject.Properties.Name -contains 'nextLink') {
                    $next = $response.nextLink
                } elseif ($response.PSObject.Properties.Name -contains 'NextPageLink') {
                    $next = $response.NextPageLink
                }
                $url = $next
            } else {
                $accumulator.Add($response)
                $url = $null
            }
        } else {
            $url = $null
        }
    }

    return $accumulator.ToArray()
}

#
# Sentinel-As-Code/Tools/Documenter/Private/Invoke-SentinelRest.ps1
#
# Created by noodlemctwoodle on 06/05/2026.
#

<#
.SYNOPSIS
    Paginating wrapper around Invoke-AzRestMethod for Sentinel and Azure Resource Manager
    REST endpoints.

.DESCRIPTION
    The Az.SecurityInsights cmdlets do not cover the full Sentinel REST surface, Codeless
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
      embedded one, saves every caller from string-building.

    Read-only by design: only GET requests. The collector should never mutate the tenant.

.PARAMETER Path
    The resource path or full URL to call. If a path is given (starting with /) the
    Invoke-AzRestMethod default ARM endpoint is used. If a fully qualified URL is given
    it is passed through (e.g. an ARM paginator nextLink).

.PARAMETER ApiVersion
    The api-version to embed in the query string when not already present.

.PARAMETER ThrowOn404
    Treat 404 as a hard error rather than the empty-collection signal.

.PARAMETER MaxAttempts
    Maximum retry attempts (default 5). Each retry waits 2^(attempt-1) seconds plus jitter.

.OUTPUTS
    [PSCustomObject[]], the flattened 'value' collection, or for endpoints that return a
    single object, the object itself wrapped in a single-element array.

.EXAMPLE
    Invoke-SentinelRest -Path '/subscriptions/.../providers/Microsoft.SecurityInsights/dataConnectorDefinitions' -ApiVersion '2024-09-01'

.NOTES
    Author:         noodlemctwoodle
    Component:      Sentinel Documenter
    Last Updated:   2026-05-13

    Multi-cloud:
      Invoke-AzRestMethod automatically routes ARM calls to the audience of the
      active Az context. To target a sovereign cloud, connect once before
      running the collector:
        Connect-AzAccount -Environment AzureUsGovernment
      All subsequent Invoke-SentinelRest calls then resolve against the
      AzureUsGovernment management endpoint without any URL substitution in
      this helper.

    Token refresh:
      Az.Accounts 2.x+ auto-refreshes the bearer token on each Invoke-AzRestMethod
      call when the current token is within ~5 minutes of expiry. Long-running
      collections against very large workspaces therefore do not need an
      explicit refresh in this helper. If a future enhancement needs to force
      a refresh boundary (e.g. for ETag-style coordination), use
      `Get-AzAccessToken -AsSecureString` and pass it via the appropriate Az
      cmdlet, direct Invoke-RestMethod with a manually-cached header is
      explicitly NOT the pattern this helper uses, by design.
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

    # Build initial URL, embed api-version if the caller hasn't already.
    # NOTE: do NOT write the interpolation as "$url$separator`api-version=..."
    # The backtick before 'a' is parsed as the bell-character escape (`a == \x07),
    # so the URL emitted to Azure becomes  ".../?<BEL>pi-version=..."
    # Azure rejects that with HTTP 400 'MissingApiVersionParameter'. Use the
    # ${var} subexpression form so the variable boundary is explicit and no
    # escape interpretation happens.
    $url = $Path
    if ($ApiVersion -and ($url -notmatch '[?&]api-version=')) {
        $separator = if ($url -match '\?') { '&' } else { '?' }
        $url = "${url}${separator}api-version=${ApiVersion}"
    }

    $accumulator = New-Object System.Collections.Generic.List[object]

    while ($url) {
        $attempt = 0
        $response = $null

        while ($true) {
            $attempt++

            try {
                # Determine the auth+transport for this URL.
                #   - Absolute URL with the ARM audience (e.g. an ARM
                #     paginator's nextLink starting `https://management.azure.com/`)
                #     needs the active Az bearer token, so strip the host
                #     and route through Invoke-AzRestMethod.
                #   - Any other absolute URL is treated as anonymous (the
                #     public Retail Prices API is the only known caller).
                #   - Otherwise the path is ARM-relative, Invoke-AzRestMethod.
                # Recognised ARM hosts across every published Azure cloud:
                #   management.azure.com, public
                #   management.usgovcloudapi.net, US Gov
                #   management.chinacloudapi.cn, Mooncake
                #   management.microsoftazure.de, Germany (legacy, retained for completeness)
                # Restricting the regex to the public host stripped the bearer
                # token from paginator nextLinks on sovereign clouds, breaking
                # every 2nd-page ARM call with a 401.
                $armHostPattern   = '^https?://management\.(azure|usgovcloudapi|chinacloudapi|microsoftazure)\.[a-z.]+/'
                $armHostPrefixPat = '^https?://management\.(azure|usgovcloudapi|chinacloudapi|microsoftazure)\.[a-z.]+'
                $isAbsolute       = $url -match '^https?://'
                $isArmAbsolute    = $isAbsolute -and ($url -match $armHostPattern)
                $effectivePath    = if ($isArmAbsolute) {
                    $url -replace $armHostPrefixPat, ''
                } else { $url }

                if ($isAbsolute -and -not $isArmAbsolute) {
                    $response = Invoke-RestMethod -Uri $url -Method Get -ErrorAction Stop
                } else {
                    $raw = Invoke-AzRestMethod -Path $effectivePath -Method GET -ErrorAction Stop
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

        # Flatten: most ARM endpoints return { value: [...], nextLink: '...' }; a few
        # return the single resource at the root, in which case 'value' is absent.
        if ($null -ne $response) {
            if ($response.PSObject.Properties.Name -contains 'value') {
                if ($response.value) {
                    foreach ($item in $response.value) { $accumulator.Add($item) }
                }
                # ARM paginates via nextLink. (The Retail Prices API uses Items +
                # NextPageLink and is paginated by its own client,
                # Get-AzureRetailPrice, not this helper.)
                $next = $null
                if ($response.PSObject.Properties.Name -contains 'nextLink') {
                    $next = $response.nextLink
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

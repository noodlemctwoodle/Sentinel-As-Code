#Requires -Version 7.2

<#
.SYNOPSIS
    The one REST client every iSOCDeployments request goes through.

.DESCRIPTION
    Replaces Invoke-SentinelApi from Modules/Sentinel.Common and the
    Invoke-GraphApi, Invoke-ArmRequest and inline Invoke-RestMethod copies in
    the scripts this module absorbs. Requests go through Invoke-AzRestMethod,
    so they are signed by the current Az sign-in, reach whichever cloud it
    is in, and never hold a token in a variable (MIGRATION.md edit E3).

.NOTES
    File:         Modules/iSOCDeployments/Private/Rest/Invoke-iSOCRestRequest.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-23
    Version:      0.1.0
    Last Updated: 2026-10-23
    Requires:     PowerShell 7.2+

    Needs Az.Accounts when it runs. The module checks for it at that point
    (Assert-iSOCPrerequisite) instead of in #Requires, so it imports
    without it.

    REST calls are only made from files under Private/Rest/, so the rest of
    the module can be tested with this one function mocked.
#>

# Keeps the file help above from being read as the help of the function below.

function Invoke-iSOCRestRequest {
    <#
    .SYNOPSIS
        Send one ARM or Graph request, following pages and retrying when the
        service asks.

    .DESCRIPTION
        - ARM paths start at /subscriptions; the api-version is added when the
          path does not carry one. Graph paths start after the version
          segment (/security/rules/detectionRules) and -ApiVersion is that
          segment (beta or v1.0). An absolute URL, such as a page link, is
          used as given.
        - A GET that returns a collection ({ "value": [...] }) is followed
          through nextLink or @odata.nextLink and the items of every page are
          returned. Anything else returns the response body as an object, or
          nothing when the body is empty.
        - 408, 429, 500, 502, 503 and 504, and connection failures, are
          retried up to -MaxAttempts times, waiting as long as Retry-After
          says, else 5, 10, 20 and 40 seconds.
        - A failure throws an error whose exception is an
          HttpRequestException carrying the status code, and whose message
          has the status, the method, the last two segments of the path and
          the service's own reason. The subscription and the host are left
          out, so the message can go in a public pipeline log.
        - The body is serialised once here (depth 100); a string is sent as
          it is.
        - Under -WhatIf a write never reaches the service: a write that gets
          here while WhatIfPreference is set throws, because the command that
          sent it skipped ShouldProcess. Reads always run, with -WhatIf
          turned off on Invoke-AzRestMethod itself.

    .PARAMETER Method
        GET, PUT, PATCH, POST or DELETE.

    .PARAMETER Path
        The ARM path, the Graph path after the version segment, or an
        absolute URL.

    .PARAMETER ApiVersion
        The ARM api-version, or the Graph version segment.

    .PARAMETER Api
        Arm (default) or Graph.

    .PARAMETER Body
        The request body: an object, serialised to JSON here, or a JSON
        string.

    .PARAMETER Context
        The workspace context. Graph requests take the Graph host from it;
        ARM requests do not need it.

    .PARAMETER AllowNotFound
        Return nothing on 404 instead of throwing.

    .PARAMETER ReadOnly
        Mark a POST that only reads (a query, a list action), so it runs
        under -WhatIf like a GET.

    .PARAMETER Raw
        Return the status code, headers and parsed body of the first
        response instead of following pages.

    .PARAMETER MaxAttempts
        Attempts before giving up, 1 to 10. Default 5.

    .OUTPUTS
        The collection's items, the response object, or with -Raw a
        [pscustomobject] StatusCode, Headers, Content.

    .EXAMPLE
        Invoke-iSOCRestRequest -Method GET -Path "$($ctx.WorkspaceResourceId)/providers/Microsoft.SecurityInsights/alertRules" -ApiVersion (Get-iSOCApiVersion SecurityInsightsPreview)

    .EXAMPLE
        Invoke-iSOCRestRequest -Method GET -Api Graph -Path '/security/rules/detectionRules' -ApiVersion beta -Context $ctx
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'ApiVersion', Justification = 'Read inside the address-building script block, which the analyser does not follow.')]
    [CmdletBinding()]
    [OutputType([psobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('GET', 'PUT', 'PATCH', 'POST', 'DELETE')]
        [string] $Method,

        [Parameter(Mandatory)]
        [string] $Path,

        [string] $ApiVersion,

        [ValidateSet('Arm', 'Graph')]
        [string] $Api = 'Arm',

        [AllowNull()]
        [object] $Body,

        [psobject] $Context,

        [switch] $AllowNotFound,

        [switch] $ReadOnly,

        [switch] $Raw,

        [ValidateRange(1, 10)]
        [int] $MaxAttempts = 5
    )

    $graphRoot = $null
    if ($Api -eq 'Graph') { $graphRoot = (Resolve-iSOCContext -Context $Context).GraphUrl }

    $resolve = {
        param([string] $Target)
        if ($Api -eq 'Arm') {
            if ($Target -match '^https?://') { $Target = $Target -replace '^https?://[^/]+', '' }
            if (-not $Target.StartsWith('/')) { throw "An ARM path starts with '/': $Target" }
            if ($ApiVersion -and $Target -notmatch '[?&]api-version=') {
                $Target += $(if ($Target.Contains('?')) { '&' } else { '?' }) + "api-version=$ApiVersion"
            }
            return $Target
        }
        if ($Target -match '^https?://') { return $Target }
        if (-not $ApiVersion) { throw 'A Graph request needs -ApiVersion: the version segment, beta or v1.0.' }
        "$graphRoot/$ApiVersion$Target"
    }

    $url = & $resolve $Path
    $segments = @((($url -split '\?')[0]) -split '/' | Where-Object { $_ })
    $short = ($segments | Select-Object -Last 2) -join '/'

    if ($Method -ne 'GET' -and -not $ReadOnly -and $WhatIfPreference) {
        throw "Internal error: $Method $short reached the REST client under -WhatIf. The command that sent it must check ShouldProcess before it writes."
    }

    $payload = $null
    if ($null -ne $Body) {
        $payload = if ($Body -is [string]) { $Body } else { ConvertTo-Json -InputObject $Body -Depth 100 -Compress }
    }

    $items = [System.Collections.Generic.List[object]]::new()
    $first = $true
    while ($url) {
        $response = $null
        $failure = $null
        for ($attempt = 1; ; $attempt++) {
            $call = @{ Method = $Method; ErrorAction = 'Stop'; WhatIf = $false; Confirm = $false }
            if ($Api -eq 'Arm') { $call.Path = $url }
            else { $call.Uri = $url; $call.ResourceId = "$graphRoot/" }
            if ($null -ne $payload) { $call.Payload = $payload }

            Write-iSOCLog "$Method $short (attempt $attempt)" -Level Debug
            $response = $null
            $failure = $null
            try { $response = Invoke-AzRestMethod @call }
            catch { $failure = $_ }

            $status = if ($response) { [int]$response.StatusCode } else { 0 }
            $transient = $false
            if ($failure) {
                $ex = $failure.Exception
                while ($ex) {
                    if ($ex -is [System.Net.Http.HttpRequestException] -or $ex -is [System.Threading.Tasks.TaskCanceledException] -or
                        $ex -is [System.IO.IOException] -or $ex -is [System.TimeoutException]) { $transient = $true; break }
                    $ex = $ex.InnerException
                }
            }
            elseif ($status -in 408, 429, 500, 502, 503, 504) { $transient = $true }

            if ($transient -and $attempt -lt $MaxAttempts) {
                $headers = if ($response) { $response.Headers } else { $null }
                $delay = Get-iSOCRestRetryDelay -Headers $headers -Attempt $attempt
                $why = if ($response) { "HTTP $status" } else { $failure.Exception.Message }
                Write-iSOCLog "$Method $short failed ($why); retrying in ${delay}s (attempt $attempt of $MaxAttempts)." -Level Warning
                Start-Sleep -Seconds $delay
                continue
            }
            break
        }

        if (-not $response) {
            throw "$Method $short failed: $($failure.Exception.Message)"
        }
        if ($status -eq 404 -and $AllowNotFound -and $first) { return }
        if ($status -ge 400) {
            $detail = Get-iSOCRestErrorDetail -Content $response.Content
            $exception = [System.Net.Http.HttpRequestException]::new("HTTP $status from $Method ${short}: $detail", $null, [System.Net.HttpStatusCode]$status)
            throw [System.Management.Automation.ErrorRecord]::new($exception, "iSOCRest.Http$status", [System.Management.Automation.ErrorCategory]::InvalidOperation, $short)
        }

        $content = $null
        if (-not [string]::IsNullOrWhiteSpace($response.Content)) { $content = $response.Content | ConvertFrom-Json }

        if ($Raw) {
            return [pscustomobject]@{
                PSTypeName = 'iSOCDeployments.RestResponse'
                StatusCode = $status
                Headers    = $response.Headers
                Content    = $content
            }
        }

        $isCollection = $Method -eq 'GET' -and $null -ne $content -and $content.PSObject.Properties['value'] -and ($content.value -is [System.Array])
        if (-not $isCollection) {
            if ($first) { return $content }
            break
        }

        foreach ($item in $content.value) { $items.Add($item) }
        $next = $null
        foreach ($name in 'nextLink', '@odata.nextLink') {
            if ($content.PSObject.Properties[$name] -and $content.$name) { $next = [string]$content.$name }
        }
        $url = if ($next) { & $resolve $next } else { $null }
        $payload = $null
        $first = $false
    }

    $items.ToArray()
}

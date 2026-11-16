#Requires -Version 7.2

<#
.SYNOPSIS
    Sends a read-only request to Azure Resource Manager with throttling
    and transient-only retry.

.NOTES
    File:         Content/Workbooks/SentinelDataLake/SdlMigrationExport/Private/Azure/Invoke-SdlArmRequest.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.2.0
    Last Updated: 2026-11-16
    Requires:     PowerShell 7.2+

    Defines one function, dot-sourced by Export-SdlMigrationWorkbook.ps1
    (deprecated; to be replaced by the iSOCDeployments module).
#>

# Keeps the file help above from being read as the help of the function below.

function Invoke-SdlArmRequest {
    <#
    .SYNOPSIS
        Sends a read-only request to Azure Resource Manager with
        throttling and transient-only retry.

    .DESCRIPTION
        Accepts a relative ARM path or an absolute URI (ARM nextLink
        values are absolute). Only transient failures (HTTP 429, 503,
        504 and transport exceptions) are retried with exponential
        back-off. An expired or interactive sign-in and any other HTTP
        error are thrown at once, so a permissions problem fails fast
        instead of burning the back-off budget. Only GET is allowed:
        the exporter never changes the workspace.

    .PARAMETER Connection
        The connection object; its ThrottleMs sets the pause after
        every call.

    .PARAMETER Path
        Relative ARM path including api-version, or an absolute URI.

    .PARAMETER Method
        The HTTP method. Only GET is accepted.

    .PARAMETER Retries
        How many attempts to make for transient failures.

    .OUTPUTS
        The response body converted from JSON.
    #>
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([object])]
    param (
        [Parameter(Mandatory)]
        [object]$Connection,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter()]
        [ValidateSet('GET')]
        [string]$Method = 'GET',

        [Parameter()]
        [ValidateRange(1, 10)]
        [int]$Retries = 3
    )

    $request = @{ Method = $Method }
    if ($Path -match '^https?://') {
        $request['Uri'] = $Path
    } else {
        $request['Path'] = $Path
    }

    $attempt = 0
    while ($true) {
        $attempt++
        Write-Verbose -Message "ARM $Method $Path (attempt $attempt of $Retries)"
        $response = $null
        $transient = $null
        try {
            $response = Invoke-AzRestMethod @request -ErrorAction Stop
        } catch {
            # Broad on purpose: Az surfaces transport failures as several
            # exception types. Authentication failures are told apart by message
            # below and thrown at once; the rest are retried.
            $transient = $_.Exception.Message
        } finally {
            Start-Sleep -Milliseconds $Connection.ThrottleMs
        }

        if ($transient -match 'Connect-AzAccount|credentials have not been set up|Authentication failed|AADSTS') {
            throw "ARM $Method $Path failed because the Azure sign-in expired or needs interaction (MFA / conditional access). Run Connect-AzAccount (add -Tenant <tenant-id>) and re-run. Detail: $transient"
        }
        if (-not $transient -and $response.StatusCode -in @(429, 503, 504)) {
            $transient = "HTTP $($response.StatusCode)"
        }
        if ($transient) {
            if ($attempt -ge $Retries) {
                throw "ARM $Method $Path failed after $attempt attempts: $transient"
            }
            $wait = [Math]::Pow(2, $attempt)
            Write-Warning -Message "ARM $transient - retrying in ${wait}s ($attempt/$Retries)"
            Start-Sleep -Seconds $wait
            continue
        }
        if ($response.StatusCode -ge 400) {
            throw "ARM $Method $Path returned HTTP $($response.StatusCode): $($response.Content)"
        }
        return ($response.Content | ConvertFrom-Json -Depth 50)
    }
}

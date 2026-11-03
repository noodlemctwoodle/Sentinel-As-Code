#Requires -Version 7.2

<#
.SYNOPSIS
    A stand-in Content Hub for the Content Hub parity tests.

.DESCRIPTION
    Serves Tests/iSOCDeployments/Fixtures/contenthub/standin.json as the
    workspace's Content Hub would: the catalogue and its entries, the
    installed packages, content templates filtered by kind, the
    workspace's analytics rules and workbook metadata, and the writes,
    which it records and refuses for the display names the fixture lists.

    Each engine gets its own stand-in from New-ContentHubStandIn, read
    fresh from the file, because Deploy-SentinelContentHub.ps1 changes
    the objects it is given (it blanks postDeployment metadata and adds
    grouping defaults to a template's incident configuration), and one
    engine must not see the other's changes.

    Invoke-ContentHubStandIn answers one request and returns what the
    service would: Kind Object (Value), Collection (Value; FirstPage for
    the hunting query templates, the page the script read) or Error
    (Status, Code, Message). The callers in the tests shape that into
    what Invoke-SentinelApi, Invoke-AzRestMethod or Invoke-iSOCRestRequest
    return.

.NOTES
    File:         Tests/iSOCDeployments/_helpers/ContentHubStandIn.psm1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.0
    Last Updated: 2026-11-03
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Keeps the file help above from being read as the help of the function below.

function New-ContentHubStandIn {
    <#
    .SYNOPSIS
        Read the fixture into a new stand-in with an empty write log.

    .PARAMETER Path
        The fixture file.

    .OUTPUTS
        [pscustomobject] Data (the fixture) and Writes (Method, Path,
        ApiVersion and Body of every request that was not a GET).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] [string] $Path
    )

    [pscustomobject]@{
        Data   = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 100
        Writes = [System.Collections.Generic.List[object]]::new()
    }
}

function Invoke-ContentHubStandIn {
    <#
    .SYNOPSIS
        Answer one request.

    .PARAMETER StandIn
        From New-ContentHubStandIn.

    .PARAMETER Method
        The HTTP method, in any case.

    .PARAMETER Path
        The request path without the host, with or without its query.

    .PARAMETER ApiVersion
        The api-version, when the path does not carry one.

    .PARAMETER Body
        The body: an object or a JSON string.

    .OUTPUTS
        [hashtable] Kind and what it needs.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)] [psobject] $StandIn,
        [Parameter(Mandatory)] [string] $Method,
        [Parameter(Mandatory)] [string] $Path,
        [string] $ApiVersion,
        [AllowNull()] [object] $Body
    )

    $data = $StandIn.Data
    $decoded = [uri]::UnescapeDataString($Path)
    $route = ($decoded -split '\?', 2)[0]
    if (-not $ApiVersion -and $decoded -match '[?&]api-version=([^&]+)') { $ApiVersion = $Matches[1] }
    $verb = $Method.ToUpperInvariant()
    $insights = "$($data.workspace)/providers/Microsoft.SecurityInsights"
    $parsed = if ($Body -is [string]) { $Body | ConvertFrom-Json -Depth 100 } else { $Body }

    if ($verb -ne 'GET') {
        $StandIn.Writes.Add([pscustomobject]@{ Method = $verb; Path = $route; ApiVersion = $ApiVersion; Body = $Body })
        $name = $null
        if ($parsed -and $parsed.PSObject.Properties['properties'] -or ($parsed -is [System.Collections.IDictionary] -and $parsed.Contains('properties'))) {
            $properties = $parsed.properties
            if ($properties -is [System.Collections.IDictionary]) { $name = $properties['displayName'] }
            elseif ($properties -and $properties.PSObject.Properties['displayName']) { $name = $properties.displayName }
        }
        if ($verb -eq 'PUT' -and $name -and $data.refusals.PSObject.Properties[[string]$name]) {
            $refusal = $data.refusals.([string]$name)
            return @{ Kind = 'Error'; Status = [int]$refusal.status; Code = $refusal.code; Message = $refusal.message }
        }
        if ($route -match '/alertRules/([^/]+)$' -and $verb -eq 'PUT') {
            return @{ Kind = 'Object'; Value = [pscustomobject]@{ id = "$insights/alertRules/$($Matches[1])"; name = $Matches[1] } }
        }
        return @{ Kind = 'Object'; Value = $null }
    }

    switch -Regex ($route) {
        '/onboardingStates/default$' { return @{ Kind = 'Object'; Value = [pscustomobject]@{ name = 'default'; properties = [pscustomobject]@{} } } }
        '/contentProductPackages$' { return @{ Kind = 'Collection'; Value = @($data.catalogue) } }
        '/contentProductPackages/([^/]+)$' {
            $entry = $data.products.PSObject.Properties[$Matches[1]]
            if ($entry) { return @{ Kind = 'Object'; Value = $entry.Value } }
            return @{ Kind = 'Error'; Status = 404; Code = 'NotFound'; Message = "No product package $($Matches[1])." }
        }
        '/contentPackages$' { return @{ Kind = 'Collection'; Value = @($data.installed) } }
        '/contentTemplates$' {
            $kinds = @([regex]::Matches($decoded, "contentKind eq '([^']+)'") | ForEach-Object { $_.Groups[1].Value })
            $found = @($data.templates | Where-Object { $_.properties.contentKind -in $kinds })
            if ($kinds -contains 'HuntingQuery') { return @{ Kind = 'Collection'; Value = $found; FirstPage = @($found | Select-Object -First ([int]$data.huntingQueryFirstPage)) } }
            return @{ Kind = 'Collection'; Value = $found }
        }
        '/contentTemplates/([^/]+)$' {
            $detail = $data.templateDetails.PSObject.Properties[$Matches[1]]
            if ($detail) { return @{ Kind = 'Object'; Value = $detail.Value } }
            return @{ Kind = 'Error'; Status = 404; Code = 'NotFound'; Message = "No content template $($Matches[1])." }
        }
        '/alertRules$' { return @{ Kind = 'Collection'; Value = @($data.alertRules) } }
        '/metadata$' { return @{ Kind = 'Collection'; Value = @($data.workbookMetadata) } }
    }
    @{ Kind = 'Error'; Status = 404; Code = 'NotFound'; Message = "The stand-in does not serve GET $route." }
}

Export-ModuleMember -Function New-ContentHubStandIn, Invoke-ContentHubStandIn

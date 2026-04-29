#
# Sentinel-As-Code/Modules/Sentinel.Common/Sentinel.Common.psm1
#
# Created by noodlemctwoodle on 29/04/2026.
#

<#
.SYNOPSIS
    Shared helpers used across the Sentinel-As-Code deployer scripts and the
    drift-detection script. Removes the byte-identical Write-PipelineMessage
    duplication and consolidates the divergent Invoke-SentinelApi /
    Connect-AzureEnvironment copies onto a single source of truth per
    Wave 4 plan Item 1.

.DESCRIPTION
    Three exported functions:

    - Write-PipelineMessage — ADO/GitHub/local-friendly logging abstraction.
      Same output shape regardless of platform; callers do not need to care
      where the script runs.

    - Invoke-SentinelApi — REST-API wrapper with retry-on-transient-failure
      semantics (HTTP 429 / 500 / 502 / 503 / 504), defensive response-body
      recovery via StreamReader for non-JSON error responses, and
      typed-exception throw on terminal failure.

    - Connect-AzureEnvironment — Az PowerShell context bootstrap with
      government-cloud branching, optional separate playbook resource group,
      access-token acquisition (with profile-client fallback for environments
      where Get-AzAccessToken is restricted), and workspace ID retrieval.
      Returns a hashtable of derived state the caller assigns to its own
      script scope (callers historically relied on the function mutating
      script scope in-place; that pattern doesn't survive module extraction
      because $script: in a module refers to the module's scope, not the
      caller's).

.NOTES
    Author:         noodlemctwoodle
    Version:        1.0.0
    Last Updated:   2026-04-29
    Repository:     Sentinel-As-Code
    Requires:       PowerShell 7.2+, Az.Accounts
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ===========================================================================
# Write-PipelineMessage
# ===========================================================================
# Byte-identical across all four pre-extraction copies (Deploy-CustomContent,
# Deploy-SentinelContentHub, Deploy-DefenderDetections, Test-SentinelRuleDrift).
# Direct copy.
function Write-PipelineMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Message
        ,
        [Parameter(Mandatory = $false)]
        [ValidateSet("Info", "Warning", "Error", "Section", "Success", "Debug")]
        [string]$Level = "Info"
    )

    $isAdo = $null -ne $env:BUILD_BUILDID

    switch ($Level) {
        "Info"    {
            Write-Host $Message
        }
        "Warning" {
            if ($isAdo) {
                Write-Host "##[warning]$Message"
            }
            else {
                Write-Warning $Message
            }
        }
        "Error"   {
            if ($isAdo) {
                Write-Host "##[error]$Message"
            }
            else {
                Write-Error $Message -ErrorAction Continue
            }
        }
        "Section" {
            if ($isAdo) {
                Write-Host "##[section]$Message"
            }
            else {
                Write-Host "`n$Message" -ForegroundColor Cyan
            }
        }
        "Success" {
            if ($isAdo) {
                Write-Host $Message
            }
            else {
                Write-Host $Message -ForegroundColor Green
            }
        }
        "Debug"   {
            Write-Verbose $Message
        }
    }
}

# ===========================================================================
# Invoke-SentinelApi
# ===========================================================================
# Source of truth: Deploy-SentinelContentHub.ps1 (lines 284-358 pre-extraction).
# This implementation has the most defensive error-recovery pattern:
# StreamReader-based response-body extraction for non-JSON 4xx/5xx responses,
# fallback to ErrorDetails.Message, retry on documented-transient HTTP codes.
function Invoke-SentinelApi {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri
        ,
        [Parameter(Mandatory = $true)]
        [string]$Method
        ,
        [Parameter(Mandatory = $true)]
        [hashtable]$Headers
        ,
        [Parameter(Mandatory = $false)]
        [string]$Body
        ,
        [Parameter(Mandatory = $false)]
        [int]$MaxRetries = 3
        ,
        [Parameter(Mandatory = $false)]
        [int]$RetryDelaySeconds = 5
    )

    $attempt = 0

    while ($attempt -lt $MaxRetries) {
        $attempt++

        try {
            $params = @{
                Uri         = $Uri
                Method      = $Method
                Headers     = $Headers
                ContentType = 'application/json'
            }

            if ($Body) {
                $params.Body = $Body
            }

            $webResponse = Invoke-WebRequest @params -UseBasicParsing -ErrorAction Stop
            return ($webResponse.Content | ConvertFrom-Json)
        }
        catch {
            $statusCode = $null
            $responseBody = $null

            # Strict-mode-safe property access: $_.Exception.Response only
            # exists on WebException-flavoured errors. Vanilla [Exception]
            # instances hit a property-not-found under Set-StrictMode without
            # this guard. Use the PSObject reflection API which returns null
            # on absence rather than throwing.
            $responseProperty = $_.Exception.PSObject.Properties['Response']
            if ($responseProperty -and $responseProperty.Value) {
                $exResponse = $responseProperty.Value
                $statusCode = [int]$exResponse.StatusCode
                try {
                    $stream = $exResponse.GetResponseStream()
                    $reader = [System.IO.StreamReader]::new($stream)
                    $responseBody = $reader.ReadToEnd()
                    $reader.Dispose()
                }
                catch { }
            }

            $errorDetailsProp = $_.PSObject.Properties['ErrorDetails']
            if (-not $responseBody -and $errorDetailsProp -and $errorDetailsProp.Value -and $errorDetailsProp.Value.Message) {
                $responseBody = $errorDetailsProp.Value.Message
            }

            # Retry on throttling (429) or transient server errors (500, 502, 503, 504)
            $retryableCodes = @(429, 500, 502, 503, 504)
            if ($statusCode -and $retryableCodes -contains $statusCode -and $attempt -lt $MaxRetries) {
                $delay = $RetryDelaySeconds * $attempt
                Write-PipelineMessage "API call returned $statusCode. Retrying in ${delay}s (attempt $attempt of $MaxRetries)..." -Level Warning
                Start-Sleep -Seconds $delay
                continue
            }

            $errorDetail = if ($responseBody) { "HTTP $statusCode - $responseBody" } else { $_.Exception.Message }
            throw "API call failed: $errorDetail"
        }
    }
}

# ===========================================================================
# Connect-AzureEnvironment
# ===========================================================================
# Source of truth: Deploy-CustomContent.ps1 (lines 654-757 pre-extraction).
# That version had the most-complete behaviour: playbook-RG validation +
# workspace-ID retrieval + profile-client token fallback.
#
# Refactor for the module: the original mutated $script: scope of the caller
# directly. That doesn't work across a module boundary (the module's $script:
# is the module's scope, not the caller's). The function now takes explicit
# parameters and returns a hashtable of derived state. Callers assign to
# their own script-scope vars:
#
#     $ctx = Connect-AzureEnvironment -ResourceGroup $ResourceGroup `
#                                     -Workspace $Workspace `
#                                     -Region $Region `
#                                     -SubscriptionId $script:SubscriptionId `
#                                     -IsGov:$IsGov `
#                                     -PlaybookResourceGroup $PlaybookResourceGroup
#     $script:SubscriptionId      = $ctx.SubscriptionId
#     $script:ServerUrl           = $ctx.ServerUrl
#     $script:BaseUri             = $ctx.BaseUri
#     $script:WorkspaceResourceId = $ctx.WorkspaceResourceId
#     $script:WorkspaceId         = $ctx.WorkspaceId
#     $script:PlaybookRG          = $ctx.PlaybookRG
#     $script:AuthHeader          = $ctx.AuthHeader
function Connect-AzureEnvironment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroup
        ,
        [Parameter(Mandatory = $true)]
        [string]$Workspace
        ,
        [Parameter(Mandatory = $true)]
        [string]$Region
        ,
        [Parameter(Mandatory = $false)]
        [string]$SubscriptionId
        ,
        [Parameter(Mandatory = $false)]
        [switch]$IsGov
        ,
        [Parameter(Mandatory = $false)]
        [string]$PlaybookResourceGroup
        ,
        [Parameter(Mandatory = $false)]
        [string]$WorkspaceApiVersion = "2022-10-01"
    )

    Write-PipelineMessage "Establishing Azure authentication..." -Level Section

    # Suppress Az module version upgrade warnings
    Update-AzConfig -DisplayBreakingChangeWarning $false -ErrorAction SilentlyContinue -WarningAction SilentlyContinue | Out-Null

    $context = Get-AzContext -WarningAction SilentlyContinue

    if (-not $context) {
        Write-PipelineMessage "No Azure context found. Attempting login..." -Level Info
        if ($IsGov) {
            Connect-AzAccount -Environment AzureUSGovernment -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null
        }
        else {
            Connect-AzAccount -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null
        }
        $context = Get-AzContext -WarningAction SilentlyContinue
    }

    if (-not $context) {
        throw "Failed to establish Azure context. Ensure you are authenticated."
    }

    # Resolve subscription: prefer explicit parameter, else current context.
    if ($SubscriptionId) {
        Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null
        $context = Get-AzContext -WarningAction SilentlyContinue
    }
    else {
        $SubscriptionId = $context.Subscription.Id
    }

    Write-PipelineMessage "Authenticated to subscription: $($context.Subscription.Id) ($($context.Subscription.Name))" -Level Success

    $serverUrl = if ($IsGov) {
        "https://management.usgovcloudapi.net"
    }
    else {
        "https://management.azure.com"
    }

    $baseUri = "$serverUrl/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$Workspace"
    $workspaceResourceId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$Workspace"
    $playbookRG = if ($PlaybookResourceGroup) { $PlaybookResourceGroup } else { $ResourceGroup }

    # Acquire access token. Try Get-AzAccessToken first; fall back to the
    # profile client for environments where the cmdlet is restricted.
    try {
        $tokenResponse = Get-AzAccessToken -ResourceUrl $serverUrl -ErrorAction Stop -WarningAction SilentlyContinue

        if ($tokenResponse.Token -is [System.Security.SecureString]) {
            $accessToken = $tokenResponse.Token | ConvertFrom-SecureString -AsPlainText
        }
        elseif ($tokenResponse.Token -is [string]) {
            $accessToken = $tokenResponse.Token
        }
        else {
            throw "Unexpected token type: $($tokenResponse.Token.GetType().FullName)"
        }
    }
    catch {
        Write-PipelineMessage "Get-AzAccessToken failed ($($_.Exception.Message)). Falling back to context profile token." -Level Warning
        $instanceProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile
        $profileClient = New-Object -TypeName Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient -ArgumentList ($instanceProfile)
        $tokenObj = $profileClient.AcquireAccessToken($context.Subscription.TenantId)
        $accessToken = $tokenObj.AccessToken
    }

    if (-not $accessToken) {
        throw "Failed to acquire an access token. Check Service Principal permissions."
    }

    $authHeader = @{
        'Content-Type'  = 'application/json'
        'Authorization' = "Bearer $accessToken"
    }

    Write-PipelineMessage "Target workspace: $Workspace (Resource Group: $ResourceGroup, Region: $Region)" -Level Info
    if ($playbookRG -ne $ResourceGroup) {
        $playbookRgCheck = Get-AzResourceGroup -Name $playbookRG -ErrorAction SilentlyContinue
        if (-not $playbookRgCheck) {
            throw "Playbook resource group '$playbookRG' does not exist. Create it via Bicep (set the playbookRgName parameter in main.bicep) or manually in the Azure portal before running the pipeline."
        }
        Write-PipelineMessage "Playbooks will deploy to resource group: $playbookRG" -Level Info
    }
    if ($IsGov) {
        Write-PipelineMessage "Azure Government cloud mode enabled." -Level Info
    }

    # Retrieve the workspace ID (GUID) for playbook parameter injection.
    # Non-fatal — proceed with $null on failure.
    $workspaceId = $null
    try {
        $wsUri = "$serverUrl/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.OperationalInsights/workspaces/${Workspace}?api-version=$WorkspaceApiVersion"
        $wsResponse = Invoke-SentinelApi -Uri $wsUri -Method Get -Headers $authHeader
        $workspaceId = $wsResponse.properties.customerId
        Write-PipelineMessage "Workspace ID: $workspaceId" -Level Info
    }
    catch {
        Write-PipelineMessage "Could not retrieve workspace ID: $($_.Exception.Message)" -Level Warning
    }

    return @{
        SubscriptionId      = $SubscriptionId
        ServerUrl           = $serverUrl
        BaseUri             = $baseUri
        WorkspaceResourceId = $workspaceResourceId
        WorkspaceId         = $workspaceId
        PlaybookRG          = $playbookRG
        AuthHeader          = $authHeader
    }
}

# ===========================================================================
# Dependency-Discovery Helpers
# ===========================================================================
# Used by Scripts/Build-DependencyManifest.ps1 to derive dependencies.json
# from content sources rather than hand-maintaining the manifest.
#
# Each Get-Kql*Reference function takes a KQL string and returns the array
# of detected dependency aliases / URLs. These are regex-based, not a full
# KQL parser, but they handle every real-world rule pattern observed in
# the repo today (see Tests/Test-SentinelCommon.Tests.ps1 for fixtures).

function Remove-KqlComments {
<#
.SYNOPSIS
    Strip KQL line and block comments from a query string before regex
    extraction so commented-out _GetWatchlist / externaldata calls do
    not produce false positives in the manifest.
#>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string]$Query)

    # Strip /* ... */ block comments first (greedy single-line, lazy
    # multi-line via singleline mode).
    $stripped = [regex]::Replace($Query, '/\*.*?\*/', '', 'Singleline')

    # Strip // line comments to end of line. The negative lookbehind (?<!:)
    # is critical — without it the regex would also match the // in URLs
    # like https://foo.com and chop off the URL host. KQL line comments
    # never legitimately follow a colon (the comment marker has to be
    # whitespace-preceded or at start of line), so excluding ':' is safe.
    $stripped = [regex]::Replace($stripped, '(?<!:)//[^\r\n]*', '')
    return $stripped
}

function Get-KqlWatchlistReferences {
<#
.SYNOPSIS
    Extract every watchlist alias referenced via _GetWatchlist('alias')
    or _GetWatchlist("alias") in the supplied KQL query.

.OUTPUTS
    String[] of distinct alias names. Returns @() when no references found.
#>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string]$Query)

    if ([string]::IsNullOrWhiteSpace($Query)) { return @() }
    $clean = Remove-KqlComments -Query $Query

    $matches = [regex]::Matches($clean, "_GetWatchlist\s*\(\s*['""]([^'""]+)['""]\s*\)")
    return @($matches | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
}

function Get-KqlExternalDataReferences {
<#
.SYNOPSIS
    Extract every URL referenced by an `externaldata(...)` operator's
    bracket list in the supplied KQL query.

.DESCRIPTION
    The KQL pattern is:
        externaldata(col1: type, col2: type) ["https://..."] with(...)

    The URL list can contain multiple entries; we extract every one.

.OUTPUTS
    String[] of distinct URLs. Returns @() when no references found.
#>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string]$Query)

    if ([string]::IsNullOrWhiteSpace($Query)) { return @() }
    $clean = Remove-KqlComments -Query $Query

    # Match the whole 'externaldata(...) [ ... ]' block, then pull URL
    # literals from the bracket list. Singleline so the match spans newlines.
    $blockRegex = [regex]::new('externaldata\s*\([^)]+\)\s*\[(?<urls>[^\]]+)\]', 'IgnoreCase, Singleline')
    $urlRegex   = [regex]::new('["''](?<url>https?://[^"'']+)["'']')

    $found = [System.Collections.Generic.List[string]]::new()
    foreach ($block in $blockRegex.Matches($clean)) {
        foreach ($urlMatch in $urlRegex.Matches($block.Groups['urls'].Value)) {
            [void]$found.Add($urlMatch.Groups['url'].Value)
        }
    }
    return @($found | Sort-Object -Unique)
}

function Get-KqlBareIdentifiers {
<#
.SYNOPSIS
    Extract bare identifiers that look like table or function references
    in a KQL query — anything that appears at a position where a data
    source is expected (start of a query, after `union`, after `let X =`,
    after `from`, after `|` followed by a data-producing operator like
    `union`, `lookup`, `mv-apply`).

.DESCRIPTION
    Heuristic regex-based extraction. Caller classifies each identifier
    as table-vs-function via the known-functions / known-tables lookups.

    Exclusions baked in: KQL keywords, known operators, single-character
    names (almost certainly let-variable references), let-bound locals,
    lambda parameters, and any identifier appearing inside a string
    literal (e.g. "POP" / "SMTP" in dynamic([...]) blocks must NOT be
    confused with table references).

.OUTPUTS
    String[] of distinct candidate identifiers.
#>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string]$Query)

    if ([string]::IsNullOrWhiteSpace($Query)) { return @() }
    $clean = Remove-KqlComments -Query $Query

    # BEFORE stripping string literals: capture table names passed as
    # string arguments to KQL's `table()` function. Pattern used by
    # lambda wrappers like:
    #
    #   let aadFunc = (tableName: string) { table(tableName) | ... };
    #   let aadSignin = aadFunc("SigninLogs");
    #
    # The actual table identifier ("SigninLogs") never appears as a
    # bare token — only as a string arg to aadFunc, which the lambda
    # forwards to `table()`. Capturing both invocation styles
    # (table('X') / table("X") AND any user-defined function called
    # with a single string arg that the function then forwards to
    # table()) is hard without a real parser; we approximate by
    # capturing every `funcName('X')` and `funcName("X")` where the
    # surrounding query also contains `table(<paramName>)` and the
    # called function's lambda declared <paramName> as a string.
    #
    # Pragmatic compromise: extract string args from any call
    # immediately following an identifier IF the query also contains
    # the literal `table(` token. This produces the right answer for
    # the lambda-table pattern and a small number of false positives
    # (string args to other funcs like _GetWatchlist) — the
    # _GetWatchlist case is already filtered by other rules so it
    # doesn't cause real noise.
    $tableStringRefs = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase)
    if ($clean -match '\btable\s*\(') {
        # Direct table('X') / table("X") calls with a literal name.
        foreach ($m in [regex]::Matches($clean, '\btable\s*\(\s*[''"]([A-Za-z_][A-Za-z0-9_]*)[''"]\s*\)')) {
            [void]$tableStringRefs.Add($m.Groups[1].Value)
        }
        # Indirect: user-defined function called with a string literal.
        # Match `Identifier ( "..." )` and `Identifier ( '...' )` and
        # capture only candidates that look like table names
        # (start with a capital letter, no spaces). Filtering happens
        # at the end via the function-called set so KQL builtins
        # (iff, isempty, replace_regex, etc.) don't slip through.
        foreach ($m in [regex]::Matches($clean, '\b([A-Za-z_][A-Za-z0-9_]*)\s*\(\s*[''"]([A-Z][A-Za-z0-9_]*)[''"]\s*\)')) {
            $candidate = $m.Groups[2].Value
            # Must look like a table — start with capital, contain underscore
            # or be a known table-naming pattern. Conservative filter to
            # avoid grabbing every string that gets passed to a function.
            if ($candidate -cmatch '^[A-Z]' -and $candidate.Length -gt 2) {
                [void]$tableStringRefs.Add($candidate)
            }
        }
    }

    # Strip string literals before any further parsing so identifiers and
    # `;` characters inside strings (e.g. "Other clients; POP") don't
    # become spurious statement-separators or candidate identifiers.
    # Cover both single- and double-quoted strings.
    $clean = [regex]::Replace($clean, '"[^"\r\n]*"', '""')
    $clean = [regex]::Replace($clean, "'[^'\r\n]*'", "''")

    # KQL keywords / operators to exclude from candidate list.
    $kqlKeywords = @(
        'let', 'set', 'where', 'project', 'extend', 'summarize', 'order', 'sort', 'top',
        'take', 'limit', 'distinct', 'count', 'count_', 'as', 'asc', 'desc', 'by',
        'and', 'or', 'not', 'in', 'between', 'contains', 'startswith', 'endswith', 'matches',
        'has', 'has_any', 'has_all', 'hasprefix', 'hassuffix',
        'true', 'false', 'null', 'dynamic', 'datetime', 'timespan', 'string', 'int', 'long',
        'real', 'double', 'bool', 'guid', 'decimal',
        'union', 'join', 'lookup', 'inner', 'leftouter', 'rightouter', 'fullouter',
        'kind', 'isfuzzy', 'on', 'with', 'hint',
        'parse', 'extract', 'split', 'replace', 'strcat', 'tolower', 'toupper', 'tostring',
        'todynamic', 'toint', 'tolong', 'tobool', 'todouble', 'todatetime', 'totimespan',
        'isempty', 'isnotempty', 'isnull', 'isnotnull', 'iif', 'iff', 'case',
        'now', 'ago', 'startofday', 'endofday', 'startofweek', 'endofweek',
        'bin', 'bin_at', 'floor', 'ceiling', 'round', 'abs', 'min', 'max', 'sum', 'avg',
        'arg_max', 'arg_min', 'dcount', 'countif', 'sumif', 'make_list', 'make_set',
        'mv-expand', 'mv-apply', 'mv_expand', 'mv_apply', 'pack', 'pack_array', 'parse-where',
        'render', 'evaluate', 'externaldata', 'materialize', 'find',
        'datatable', 'print', 'range', 'series_decompose', 'series_decompose_anomalies',
        'invoke', 'fork',
        'true', 'false', 'null',
        'series_iir', 'series_seasonal',
        'true', 'false'
    ) | Sort-Object -Unique

    # Identifier candidates appear at three syntactic positions:
    # 1) Start of a query line (column 0 of a stripped line) — a table/function
    #    appearing directly. This is the most common pattern.
    # 2) After `let X = ` — the right-hand side may start with a table.
    # 3) After `union ` (single keyword + space) — table/function being unioned.
    # We extract from each position with separate regexes, then dedupe.
    $candidates = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )

    # Position 1: first data-source identifier per statement.
    #
    # Naive "any identifier at start of a line" is too noisy — KQL queries
    # routinely have column names appearing on continuation lines after
    # `project` / `extend` / `summarize ... by`. The discriminator: a table
    # reference appears at the BEGINNING of a statement, where statements
    # are delimited by `;` (KQL's statement terminator). Within each
    # statement, the first identifier is either the table directly or the
    # RHS of a `let X =` binding.
    $statements = $clean -split ';'
    foreach ($stmt in $statements) {
        if ([string]::IsNullOrWhiteSpace($stmt)) { continue }
        # `let X = TableName ...` → capture TableName
        if ($stmt -match '(?ms)^\s*(?:declare\s+\(.*?\)\s+)?let\s+\w+\s*=\s*\(?\s*([A-Za-z_][A-Za-z0-9_]*)\b') {
            [void]$candidates.Add($Matches[1])
        }
        # Otherwise first identifier in the statement.
        elseif ($stmt -match '(?ms)^\s*([A-Za-z_][A-Za-z0-9_]*)\b') {
            [void]$candidates.Add($Matches[1])
        }
    }

    # Position 2: after `union ` keyword (skipping any number of
    # `key=value` modifiers like `kind=outer`, `isfuzzy=true`, `hint.*=...`).
    foreach ($m in [regex]::Matches($clean, '\bunion\s+(?:[\w.]+\s*=\s*\w+\s+)*([A-Za-z_][A-Za-z0-9_]*)\b')) {
        [void]$candidates.Add($m.Groups[1].Value)
    }

    # Position 3: subquery start after a join/lookup operator. Pattern:
    #     | join kind=inner (TableName | where ...)
    #     | lookup (TableName | project ...)
    foreach ($m in [regex]::Matches($clean, '\b(?:join|lookup)\s+(?:kind\s*=\s*\w+\s+)?\(\s*([A-Za-z_][A-Za-z0-9_]*)\b')) {
        [void]$candidates.Add($m.Groups[1].Value)
    }

    # Position 4: subquery start inside a paren-wrapped block following
    # one of the KQL operators that take a tabular subquery argument:
    #     materialize (TableName | ...)
    #     view (TableName | ...)
    #     toscalar (TableName | ...)
    # The operator names themselves are KQL keywords filtered out at the
    # end; what we want is the first identifier inside the paren.
    foreach ($m in [regex]::Matches($clean, '\b(?:materialize|view|toscalar)\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)\b')) {
        [void]$candidates.Add($m.Groups[1].Value)
    }

    # Add the table-string refs collected from `table('X')` / lambda
    # forwarding patterns BEFORE the keyword/function-call filter runs.
    foreach ($r in $tableStringRefs) { [void]$candidates.Add($r) }

    # Drop candidates that are immediately followed by an opening paren
    # in the source — those are KQL function calls (e.g. `toscalar(...)`,
    # `_GetWatchlist(...)`, `materialize(...)`, `iff(...)`), not data
    # sources. Build a set of "known to be function-called" names by
    # regex over the original query.
    $functionCalled = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    foreach ($m in [regex]::Matches($clean, '\b([A-Za-z_][A-Za-z0-9_]*)\s*\(')) {
        [void]$functionCalled.Add($m.Groups[1].Value)
    }

    # Drop candidates that are LHS of a `let X =` binding OR a parameter
    # of a let-defined lambda — both are locally-scoped, not external
    # dependencies. Lambda parameters look like:
    #     let aadFunc = (tableName: string, start: datetime) { ... }
    $letBindings = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    foreach ($m in [regex]::Matches($clean, '(?m)^\s*let\s+(\w+)\s*=')) {
        [void]$letBindings.Add($m.Groups[1].Value)
    }
    # Lambda parameter detection: capture the param-list inside
    # `let X = ( ... ) { ... }` and split on `,` to get individual
    # `paramName: type` declarations.
    foreach ($m in [regex]::Matches($clean, '(?ms)\blet\s+\w+\s*=\s*\(([^)]+)\)\s*\{')) {
        $paramList = $m.Groups[1].Value
        foreach ($paramMatch in [regex]::Matches($paramList, '([A-Za-z_][A-Za-z0-9_]*)\s*:')) {
            [void]$letBindings.Add($paramMatch.Groups[1].Value)
        }
    }

    # Filter: drop KQL keywords/operators, function-call sites, let-bound
    # locals, and obvious single-character names.
    $filtered = @($candidates | Where-Object {
        $_.Length -gt 1 -and
        ($kqlKeywords -notcontains $_.ToLowerInvariant()) -and
        (-not $functionCalled.Contains($_)) -and
        (-not $letBindings.Contains($_))
    } | Sort-Object -Unique)

    return $filtered
}

function Get-ContentKqlQuery {
<#
.SYNOPSIS
    Read a content file and return its embedded KQL query text. Supports
    AnalyticalRules / HuntingQueries / Parsers (YAML, `query:` field) and
    SummaryRules (JSON, `query:` field) and DefenderCustomDetections
    (YAML, `queryCondition.queryText`).

.OUTPUTS
    String containing the KQL, or $null if the file does not match any
    known content shape or has no embedded query.
#>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [string]$Path)

    if (-not (Test-Path $Path)) { return $null }
    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    try {
        if ($extension -eq '.yaml' -or $extension -eq '.yml') {
            $yaml = ConvertFrom-Yaml (Get-Content -Path $Path -Raw -ErrorAction Stop)
            if ($null -eq $yaml -or -not ($yaml -is [System.Collections.IDictionary])) { return $null }

            # Defender custom detections nest the query under queryCondition.
            if ($yaml.ContainsKey('queryCondition') -and ($yaml['queryCondition'] -is [System.Collections.IDictionary]) -and $yaml['queryCondition'].ContainsKey('queryText')) {
                return [string]$yaml['queryCondition']['queryText']
            }
            if ($yaml.ContainsKey('query')) {
                return [string]$yaml['query']
            }
        }
        elseif ($extension -eq '.json') {
            $json = Get-Content -Path $Path -Raw -ErrorAction Stop | ConvertFrom-Json -Depth 32
            if ($json.PSObject.Properties.Name -contains 'query') {
                return [string]$json.query
            }
        }
    }
    catch {
        # Per-file content-schema test owns parse errors; this helper
        # silently returns $null when extraction fails.
    }
    return $null
}

function Get-ContentDependencies {
<#
.SYNOPSIS
    Discover the dependencies of a single content file by reading its
    embedded KQL and running every Get-Kql*Reference extractor against it.
    Classifies bare identifiers as either tables or functions, using the
    repo as the source of truth for what is deployable.

.DESCRIPTION
    Repo-driven classification model:

      - In-repo functions (Parsers/) → 'functions' bucket. These must
        deploy before any rule that references them.
      - Microsoft-provided ASIM functions (matched by regex) → 'functions'
        bucket. External, but listed for visibility.
      - Everything else at a data-source position → 'tables' bucket. This
        is the default classification: tables are external (data plane)
        and not deployable from the repo, so we do not need a hard-coded
        catalogue to list them. Custom-log tables (suffix '_CL') fall
        into this bucket as well.

    No 'unclassified' bucket: with the bare-identifier extractor filtering
    let-bound names, lambda parameters, KQL keywords and string literals,
    every remaining identifier is a real data-source reference and is
    correctly modelled as either a function or a table.

.PARAMETER Path
    Absolute or repo-relative path to the YAML/JSON content file.

.PARAMETER KnownFunctions
    Hashtable keyed by function alias (case-insensitive). Built by the
    caller from the repo's Parsers/ folder. Values can be anything; only
    the keys are used.

.PARAMETER ExternalFunctionPattern
    Optional regex pattern for Microsoft-provided ASIM/im function names
    that don't appear in the in-repo Parsers/. Default matches the
    standard ASIM nomenclature.

.OUTPUTS
    Hashtable shaped like a dependencies.json entry — keys: tables,
    watchlists, functions, externalData. Empty arrays for absent buckets.
#>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)] [string]$Path
        ,
        [Parameter()] [hashtable]$KnownFunctions = @{}
        ,
        [Parameter()] [string]$ExternalFunctionPattern = '^(_?ASim|_Im_|im)\w+$'
    )

    $result = @{
        tables       = @()
        watchlists   = @()
        functions    = @()
        externalData = @()
    }

    $query = Get-ContentKqlQuery -Path $Path
    if ([string]::IsNullOrWhiteSpace($query)) { return $result }

    $result.watchlists   = Get-KqlWatchlistReferences -Query $query
    $result.externalData = Get-KqlExternalDataReferences -Query $query

    $bareIdentifiers = Get-KqlBareIdentifiers -Query $query
    $tableSet    = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $functionSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($id in $bareIdentifiers) {
        if ($KnownFunctions.ContainsKey($id) -or $id -match $ExternalFunctionPattern) {
            [void]$functionSet.Add($id)
        }
        else {
            # Default: anything at a data-source position that isn't a
            # function is a table. Custom-log tables (_CL suffix) follow
            # the same rule. The bare-identifier extractor is responsible
            # for not handing us false positives (column names, lambda
            # params, keywords); see Get-KqlBareIdentifiers.
            [void]$tableSet.Add($id)
        }
    }

    $result.tables       = @($tableSet       | Sort-Object)
    $result.functions    = @($functionSet    | Sort-Object)
    return $result
}

Export-ModuleMember -Function `
    Write-PipelineMessage, `
    Invoke-SentinelApi, `
    Connect-AzureEnvironment, `
    Remove-KqlComments, `
    Get-KqlWatchlistReferences, `
    Get-KqlExternalDataReferences, `
    Get-KqlBareIdentifiers, `
    Get-ContentKqlQuery, `
    Get-ContentDependencies

#Requires -Version 7.2

<#
.SYNOPSIS
    How the collector reports a capture it could not read, as it runs and
    in the capture summary at the end.

.DESCRIPTION
    A capture the collector could not read has one of three outcomes:

      NotAvailable  The workspace does not have what the capture reads: a
                    table, a column or an endpoint that is not served in
                    this region, tenant or plan. Nothing to fix; the
                    capture writes an empty file.
      Permission    The service refused the identity (HTTP 401 or 403 and
                    the ARM and Graph codes that go with them). Expected
                    where the signed-in account or pipeline identity was
                    not granted that role or permission.
      Error         Anything else: a timeout, throttling, a service error.

    Each is said once as it happens, on a line of its own colour and lead
    word so it reads without colour too: "not available" in dark cyan, "no
    permission" in magenta, and an error as a warning (yellow). The capture
    summary at the end lists them under Not available, No access and
    Failed, each message wrapped under its capture, then the key captures
    that hold no data. In Azure DevOps (TF_BUILD) and GitHub Actions
    (GITHUB_ACTIONS) the No access and Failed headlines carry the platform's
    warning annotation.

.NOTES
    File:         Modules/iSOCBlueprint/Engine/Private/Write-CaptureSummary.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-15
    Version:      0.2.2
    Last Updated: 2026-10-15
    Requires:     PowerShell 7.2+

    This file defines functions rather than running.
#>

function Get-CaptureIssueKind {
    <#
    .SYNOPSIS
        Sort a capture's error: 'Permission', 'NotAvailable' or 'Error'.

    .DESCRIPTION
        A refusal (401, 403, AuthorizationFailed and the like) is Permission.
        A query naming a column its tables lack ("Failed to resolve scalar
        expression") is Error: the query's fault, to be fixed. A table or
        endpoint the workspace does not have (KQL "Failed to resolve table or
        column expression", 404, an unregistered provider or resource type)
        is NotAvailable. A timeout, throttling or service error is Error. A
        bare 400 with nothing more is NotAvailable: the collector's queries
        are parsed in its tests, so a refused query is almost always one
        that names a table this workspace lacks.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowEmptyString()] [string] $Message)

    $permission = '\b40[13]\b|Forbidden|Unauthori[sz]ed|AuthorizationFailed|AuthorizationPermissionMismatch|Authorization_RequestDenied|does not have (authorization|permission)|Insufficient privileges|InsufficientPermissions|AccessDenied|Access denied'
    # A query naming a column its tables do not have is the query's fault, not
    # the workspace's: KQL says "scalar expression" for a missing column and
    # "table or column expression" for a missing table.
    $queryBug   = 'Failed to resolve (scalar|column) expression'
    $missing    = 'Failed to resolve table|could not be resolved|\b404\b|Not ?Found|PathNotFound|ResourceNotFound|NoRegisteredProviderFound|InvalidResourceType|not (served|supported|available|enabled)|FeatureNotEnabled|does not exist'
    $failure    = 'time(d)? ?out|exceeded|too large|throttl|\b429\b|TooManyRequests|\b50\d\b|InternalServerError|ServiceUnavailable|GatewayTimeout'
    if ($Message -match $permission) { return 'Permission' }
    if ($Message -match $queryBug) { return 'Error' }
    if ($Message -match $missing) { return 'NotAvailable' }
    if ($Message -match $failure) { return 'Error' }
    if ($Message -match 'BadRequest|\b400\b') { return 'NotAvailable' }
    'Error'
}

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

function Get-CaptureStatusText {
    <#
    .SYNOPSIS
        The HTTP status a capture's error names, as "401 Unauthorized" or
        "Forbidden"; $null when it names none.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowEmptyString()] [string] $Message)

    if ($Message -match '\b(\d{3})\s*\(([A-Za-z ]+)\)') { return "$($Matches[1]) $($Matches[2])" }
    if ($Message -match 'does not indicate success: (\w+)') { return $Matches[1] }
    if ($Message -match '\b(Forbidden|Unauthori[sz]ed|AuthorizationFailed|AuthorizationPermissionMismatch|Authorization_RequestDenied|AccessDenied)\b') { return $Matches[1] }
    $null
}

function Write-CaptureNote {
    <#
    .SYNOPSIS
        Say, as it happens, that a capture could not be read and why: a line
        in the outcome's colour under the capture's label, or a warning for
        an error.

    .PARAMETER Kind
        NotAvailable, Permission or Error.

    .PARAMETER Label
        The capture's label, for an error's warning.

    .PARAMETER Text
        What happened.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateSet('NotAvailable', 'Permission', 'Error')] [string] $Kind,
        [string] $Label,
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Text
    )

    switch ($Kind) {
        'NotAvailable' { Write-Host "  ↳ not available: $Text" -ForegroundColor DarkCyan }
        'Permission'   { Write-Host "  ↳ no permission: $Text" -ForegroundColor Magenta }
        default        { Write-Warning "[$Label] FAILED: $Text" }
    }
}

function Write-PartialCaptureIssue {
    <#
    .SYNOPSIS
        One line for a capture that could not read some of its items, in
        place of a line an item, and the issues for the run summary.

    .DESCRIPTION
        Each outcome gets its own line: "no permission: the run history of
        3 of 12 playbooks (401 Unauthorized): A, B, C."

    .PARAMETER Label
        The capture's label.

    .PARAMETER What
        What could not be read, ending in "of": 'the run history of'.

    .PARAMETER Noun
        The item, singular and plural: 'playbook', 'playbooks'.

    .PARAMETER Total
        How many items the capture tried to read.

    .PARAMETER Failures
        Name and Message for each item that could not be read.

    .OUTPUTS
        [pscustomobject] Label, Kind and Message, one for each outcome, for
        the run's issue list.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Label,
        [Parameter(Mandatory)] [string] $What,
        [Parameter(Mandatory)] [string[]] $Noun,
        [int] $Total,
        [object[]] $Failures = @()
    )

    $items = if ($Total -eq 1) { $Noun[0] } else { $Noun[-1] }
    foreach ($group in @($Failures | Where-Object { $_ } | Group-Object -Property { Get-CaptureIssueKind $_.Message } | Sort-Object Name -Descending)) {
        $names = @($group.Group | ForEach-Object { [string]$_.Name } | Sort-Object -Unique)
        $statuses = @($group.Group | ForEach-Object { Get-CaptureStatusText $_.Message } | Where-Object { $_ } | Sort-Object -Unique)
        $status = if ($statuses.Count) { " ($($statuses -join ', '))" } else { '' }
        $text = "$What $($names.Count) of $Total $items${status}: $($names -join ', ')."
        if ($group.Name -eq 'Error') { $text = "could not read $text First error: $(Format-CaptureMessage ([string]$group.Group[0].Message))" }
        Write-CaptureNote -Kind $group.Name -Label $Label -Text $text
        # The summary lists it under its outcome, so it reads as a sentence.
        $sentence = switch ($group.Name) {
            'Permission'   { "No permission to read $text" }
            'NotAvailable' { "Not available: $text" }
            default        { 'C' + $text.Substring(1) }
        }
        [pscustomobject]@{ Label = $Label; Kind = $group.Name; Message = $sentence }
    }
}

function Format-WrappedText {
    <#
    .SYNOPSIS
        Text wrapped to a width under a hanging indent, one string a line.

    .PARAMETER Width
        The full line width, indent included. 0 takes the console's, or 120
        where there is no console (a pipeline agent).
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [AllowEmptyString()] [string] $Text,
        [int] $Indent = 0,
        [int] $Width = 0
    )

    if ($Width -le 0) {
        $Width = try { [int]$Host.UI.RawUI.WindowSize.Width } catch { 0 }
        if ($Width -lt 40) { $Width = 120 }
    }
    $room = [math]::Max(30, $Width - $Indent - 1)
    $pad = ' ' * $Indent
    $lines = [System.Collections.Generic.List[string]]::new()
    $line = ''
    foreach ($word in @($Text -split '\s+' | Where-Object { $_ })) {
        if ($line.Length -gt 0 -and $line.Length + 1 + $word.Length -gt $room) {
            $lines.Add("$pad$line")
            $line = $word
        } else {
            $line = if ($line) { "$line $word" } else { $word }
        }
    }
    if ($line) { $lines.Add("$pad$line") }
    $lines.ToArray()
}

function Get-CaptureFileCount {
    <#
    .SYNOPSIS
        Items in one _raw file: rows for an array file, 1 or 0 for a single
        object. $null when the file is missing, -1 when it does not parse.
    #>
    [CmdletBinding()]
    param([string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = Get-Content -LiteralPath $Path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) { return 0 }
    try { $parsed = $raw | ConvertFrom-Json -ErrorAction Stop } catch { return -1 }
    if ($raw.TrimStart().StartsWith('{')) {
        if ($null -eq $parsed -or @($parsed.PSObject.Properties).Count -eq 0) { return 0 }
        return 1
    }
    if ($null -eq $parsed) { return 0 }
    @($parsed).Count
}

function Write-CaptureSummary {
    <#
    .SYNOPSIS
        Write the capture summary to the host.

    .PARAMETER RawRoot
        The run's _raw folder.

    .PARAMETER Issues
        The captures not read in full: Label, Kind (NotAvailable, Permission
        or Error) and Message.

    .PARAMETER ExpectNonEmpty
        Files every workspace fills; empty or missing is unexpected.

    .PARAMETER ExpectIfActive
        Files an active workspace usually fills; empty is worth a look.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $RawRoot,
        [object[]] $Issues = @(),
        [string[]] $ExpectNonEmpty = @(),
        [string[]] $ExpectIfActive = @()
    )

    $annotation = if ($env:TF_BUILD) { '##[warning]' } elseif ($env:GITHUB_ACTIONS -eq 'true') { '::warning::' } else { '' }
    $row = { param([string] $Name, [string] $Value) '  {0,-15}{1}' -f $Name, $Value }
    # A headline in its outcome's colour; on a pipeline agent, a warning
    # annotation for the outcomes that need someone to act.
    $headline = {
        param([string] $Text, [string] $Colour, [bool] $NeedsAction)
        if ($NeedsAction -and $annotation) { Write-Host "$annotation$Text" }
        elseif ($Colour) { Write-Host $Text -ForegroundColor $Colour }
        else { Write-Host $Text }
    }
    $listed = {
        param([object[]] $Group, [string] $Colour)
        foreach ($i in $Group) {
            Write-Host "    $($i.Label)"
            foreach ($line in (Format-WrappedText -Text (Format-CaptureMessage ([string]$i.Message)) -Indent 8)) {
                if ($Colour) { Write-Host $line -ForegroundColor $Colour } else { Write-Host $line }
            }
        }
    }

    $all          = @($Issues | Where-Object { $_ })
    $notAvailable = @($all | Where-Object { $_.Kind -eq 'NotAvailable' })
    $permission   = @($all | Where-Object { $_.Kind -eq 'Permission' })
    $failed       = @($all | Where-Object { $_.Kind -notin 'NotAvailable', 'Permission' })
    $issueLabels  = @($all | ForEach-Object { [string]$_.Label })
    $written      = @(Get-ChildItem -LiteralPath $RawRoot -Filter '*.json' -File -ErrorAction SilentlyContinue).Count

    $problems = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($f in @($ExpectNonEmpty) + @($ExpectIfActive)) {
        $count = Get-CaptureFileCount -Path (Join-Path $RawRoot $f)
        $status = if ($null -eq $count) { 'missing' }
            elseif ($count -lt 0) { 'does not parse' }
            elseif ($count -eq 0) { if ($ExpectNonEmpty -contains $f) { 'empty, unexpected' } else { 'empty' } }
            else { $null }
        if ($status -and $issueLabels -contains [System.IO.Path]::GetFileNameWithoutExtension($f)) { $status += ' (listed above)' }
        if ($status) { $problems.Add([pscustomobject]@{ File = $f; Status = $status }) }
    }
    $keyTotal = @($ExpectNonEmpty).Count + @($ExpectIfActive).Count

    Write-Host ''
    if ($env:TF_BUILD) { Write-Host '##[section]Capture summary' } else { Write-Host 'Capture summary' -ForegroundColor Cyan }
    Write-Host (& $row 'Written' "$written files to $RawRoot")

    if ($notAvailable.Count) {
        & $headline (& $row 'Not available' "$($notAvailable.Count) capture(s) had nothing to read: a table, column or endpoint this workspace does not have.") 'DarkCyan' $false
        & $listed $notAvailable 'DarkGray'
    } else {
        Write-Host (& $row 'Not available' 'none')
    }

    if ($permission.Count) {
        & $headline (& $row 'No access' "$($permission.Count) capture(s) not read in full for want of a role or permission.") 'Magenta' $true
        foreach ($line in (Format-WrappedText -Text 'Expected where the signed-in account or pipeline identity was not granted it.' -Indent 17)) { Write-Host $line }
        & $listed $permission 'DarkGray'
    } else {
        Write-Host (& $row 'No access' 'none')
    }

    if ($failed.Count) {
        & $headline (& $row 'Failed' "$($failed.Count) capture(s) raised an error and were skipped.") 'Yellow' $true
        & $listed $failed ''
    } else {
        Write-Host (& $row 'Failed' 'none')
    }

    if ($problems.Count) {
        & $headline (& $row 'Key data' "$($problems.Count) of $keyTotal key captures hold no data:") 'Yellow' $true
        $width = ($problems | ForEach-Object { $_.File.Length } | Measure-Object -Maximum).Maximum
        foreach ($p in $problems) { Write-Host ("    {0}  {1}" -f $p.File.PadRight($width), $p.Status) }
        foreach ($line in (Format-WrappedText -Text 'Usually populated on an active workspace. If you expected data: check RBAC (Microsoft Sentinel Reader at workspace scope covers automation rules, watchlists, hunting queries and incidents) and that the workspace has been used since deployment.' -Indent 4)) { Write-Host $line }
    } else {
        Write-Host (& $row 'Key data' "all $keyTotal key captures hold data")
    }
}

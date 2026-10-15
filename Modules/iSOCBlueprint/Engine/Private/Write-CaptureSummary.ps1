#Requires -Version 7.2

<#
.SYNOPSIS
    The collector's end-of-run capture summary, and how it sorts a failed
    capture.

.DESCRIPTION
    A run under an identity without every role loses some captures: the
    service answers 401 or 403 and the collector carries on without them.
    That is expected wherever a role or Graph permission was not granted,
    so the summary lists those captures as skipped for permission, apart
    from captures that failed for any other reason, and wraps each
    message under its capture rather than letting it run across the
    terminal. Key captures that are empty or missing are listed only when
    there are some.

    In Azure DevOps (TF_BUILD) and GitHub Actions (GITHUB_ACTIONS) the
    headline lines carry the platform's warning annotation; anywhere else
    they are coloured.

.NOTES
    File:         Modules/iSOCBlueprint/Engine/Private/Write-CaptureSummary.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-15
    Version:      0.1.0
    Last Updated: 2026-10-15
    Requires:     PowerShell 7.2+

    This file defines functions rather than running.
#>

function Get-CaptureIssueKind {
    <#
    .SYNOPSIS
        'Permission' when a capture's error is a refusal for want of a role
        or permission (HTTP 401 or 403 and the ARM and Graph codes that go
        with them), else 'Error'.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowEmptyString()] [string] $Message)

    $pattern = '\b40[13]\b|Forbidden|Unauthori[sz]ed|AuthorizationFailed|AuthorizationPermissionMismatch|Authorization_RequestDenied|does not have (authorization|permission)|Insufficient privileges|InsufficientPermissions|AccessDenied|Access denied'
    if ($Message -match $pattern) { 'Permission' } else { 'Error' }
}

function Format-CaptureMessage {
    <#
    .SYNOPSIS
        A capture's error message on one line, without the HTTP client's
        "Response status code does not indicate success: X (X)" wording.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowEmptyString()] [string] $Message)

    $text = ($Message -replace '\s+', ' ').Trim()
    $text = $text -replace 'Response status code does not indicate success: (\w+) \(\1\)\.?', '$1.'
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

function Write-PartialCaptureIssue {
    <#
    .SYNOPSIS
        One warning for a capture that could not read some of its items, in
        place of a line an item, and the issues for the run summary.

    .DESCRIPTION
        Refusals for want of a permission are told apart from other errors:
        "No permission to read the run history of 3 of 12 playbooks (401
        Unauthorized): A, B, C."

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
        [pscustomobject] Label, Kind and Message, one for each kind of
        failure, for the run's issue list.
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
        $text = if ($group.Name -eq 'Permission') {
            "No permission to read $What $($names.Count) of $Total $items${status}: $($names -join ', ')."
        } else {
            "Could not read $What $($names.Count) of $Total $items${status}: $($names -join ', '). First error: $(Format-CaptureMessage ([string]$group.Group[0].Message))"
        }
        Write-Warning "[$Label] $text"
        [pscustomobject]@{ Label = $Label; Kind = $group.Name; Message = $text }
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
        The failed captures: Label, Kind (Permission or Error) and Message.

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

    $annotate = if ($env:TF_BUILD) { '##[warning]' } elseif ($env:GITHUB_ACTIONS -eq 'true') { '::warning::' } else { '' }
    $headline = {
        param([string] $Text, [bool] $Warn)
        if ($Warn -and $annotate) { Write-Host "$annotate$Text" }
        elseif ($Warn) { Write-Host $Text -ForegroundColor Yellow }
        else { Write-Host $Text }
    }
    $row = { param([string] $Name, [string] $Value) '  {0,-12}{1}' -f $Name, $Value }

    $permission = @($Issues | Where-Object { $_ -and $_.Kind -eq 'Permission' })
    $failed     = @($Issues | Where-Object { $_ -and $_.Kind -ne 'Permission' })
    $written    = @(Get-ChildItem -LiteralPath $RawRoot -Filter '*.json' -File -ErrorAction SilentlyContinue).Count

    $problems = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($f in @($ExpectNonEmpty) + @($ExpectIfActive)) {
        $count = Get-CaptureFileCount -Path (Join-Path $RawRoot $f)
        $status = if ($null -eq $count) { 'missing' }
            elseif ($count -lt 0) { 'does not parse' }
            elseif ($count -eq 0) { if ($ExpectNonEmpty -contains $f) { 'empty, unexpected' } else { 'empty' } }
            else { $null }
        if ($status) { $problems.Add([pscustomobject]@{ File = $f; Status = $status }) }
    }
    $keyTotal = @($ExpectNonEmpty).Count + @($ExpectIfActive).Count

    Write-Host ''
    if ($env:TF_BUILD) { Write-Host '##[section]Capture summary' } else { Write-Host 'Capture summary' -ForegroundColor Cyan }
    Write-Host (& $row 'Written' "$written files to $RawRoot")

    if ($permission.Count) {
        & $headline ((& $row 'No access' "$($permission.Count) capture(s) not read in full for want of a role or permission.")) $true
        foreach ($line in (Format-WrappedText -Text 'Expected where the signed-in account or pipeline identity was not granted it.' -Indent 14)) { Write-Host $line }
        foreach ($i in $permission) {
            Write-Host "    $($i.Label)"
            foreach ($line in (Format-WrappedText -Text (Format-CaptureMessage $i.Message) -Indent 8)) { Write-Host $line -ForegroundColor DarkGray }
        }
    } else {
        Write-Host (& $row 'No access' 'none')
    }

    if ($failed.Count) {
        & $headline ((& $row 'Failed' "$($failed.Count) capture(s) raised an error and were skipped.")) $true
        foreach ($i in $failed) {
            Write-Host "    $($i.Label)"
            foreach ($line in (Format-WrappedText -Text (Format-CaptureMessage $i.Message) -Indent 8)) { Write-Host $line }
        }
    } else {
        Write-Host (& $row 'Failed' 'none')
    }

    if ($problems.Count) {
        & $headline ((& $row 'Key data' "$($problems.Count) of $keyTotal key captures hold no data:")) $true
        $width = ($problems | ForEach-Object { $_.File.Length } | Measure-Object -Maximum).Maximum
        foreach ($p in $problems) { Write-Host ("    {0}  {1}" -f $p.File.PadRight($width), $p.Status) }
        foreach ($line in (Format-WrappedText -Text 'Usually populated on an active workspace. If you expected data: check RBAC (Microsoft Sentinel Reader at workspace scope covers automation rules, watchlists, hunting queries and incidents) and that the workspace has been used since deployment.' -Indent 4)) { Write-Host $line }
    } else {
        Write-Host (& $row 'Key data' "all $keyTotal key captures hold data")
    }
}

#Requires -Version 7.6

<#
.SYNOPSIS
    Write the capture summary to the host.

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
    File:         Modules/iSOCBlueprint/Private/CaptureSummary/Write-CaptureSummary.ps1
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

    $all = @($Issues | Where-Object { $_ })
    $notAvailable = @($all | Where-Object { $_.Kind -eq 'NotAvailable' })
    $permission = @($all | Where-Object { $_.Kind -eq 'Permission' })
    $failed = @($all | Where-Object { $_.Kind -notin 'NotAvailable', 'Permission' })
    $issueLabels = @($all | ForEach-Object { [string]$_.Label })
    $written = @(Get-ChildItem -LiteralPath $RawRoot -Filter '*.json' -File -ErrorAction SilentlyContinue).Count

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

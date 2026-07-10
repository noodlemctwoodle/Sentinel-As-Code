#
# Sentinel-As-Code/Tools/Test-PullRequestTemplate.ps1
#
# Created by noodlemctwoodle on 08/07/2026.
#

#Requires -Version 7.2

<#
.SYNOPSIS
    Validates that a pull-request description follows
    .github/PULL_REQUEST_TEMPLATE.md. Fails (exit 1) when a required
    section is missing, left as the placeholder guidance, or the
    "Type of change" taxonomy has no box ticked. Called by the
    "PR Template Validation" GitHub Actions workflow so an under-filled
    PR body blocks the merge gate.

.DESCRIPTION
    The PR template asks the author WHY the change is needed, WHAT it
    does, what it fixes / affects, and how it was tested. Reviewers rely
    on that context, so an empty or copy-paste body wastes review time.
    This script turns the template's required sections into an
    enforceable check.

    What it enforces (each a hard failure):

      1. The description is not empty.
      2. Every required prose section is present AND holds real content
         once the HTML guidance comments are stripped:
           - Summary
           - Why is this change needed?
           - What does this change do?
           - Testing
      3. The "Type of change" section has at least one ticked box ([x]).

    What it deliberately does NOT enforce (kept optional so contributors
    are not pushed into writing "N/A" noise):

      - "What does this fix or affect?", "Files changed",
        "Pre-merge checklist", and "Related" sections.

    The parsing logic lives in small pure functions
    (Get-PullRequestSection, Remove-MarkdownComment,
    Test-PullRequestTemplateBody) so it can be unit-tested via the
    repo's AST-extraction pattern without running this entry-point.
    See Tests/Test-PullRequestTemplate.Tests.ps1.

.PARAMETER Body
    The raw PR description (Markdown). In CI this is passed from
    github.event.pull_request.body via an environment variable so the
    untrusted body is never interpolated into a shell command.

.PARAMETER BodyPath
    Alternative to -Body: a path to a file containing the PR
    description. -Body wins if both are supplied.

.EXAMPLE
    ./Tools/Test-PullRequestTemplate.ps1 -Body $env:PR_BODY

    Validates the body captured in the PR_BODY environment variable.
    Exits 1 (with a per-failure list) if the template is under-filled.

.EXAMPLE
    ./Tools/Test-PullRequestTemplate.ps1 -BodyPath ./pr-body.md

    Validates a description read from a file. Handy for local testing.

.NOTES
    Author:         noodlemctwoodle
    Version:        1.0.0
    Last Updated:   2026-07-08
    Repository:     Sentinel-As-Code
    Requires:       PowerShell 7.2+, Sentinel.Common (logging only)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [AllowEmptyString()]
    [string]$Body
    ,
    [Parameter(Mandatory = $false)]
    [string]$BodyPath
)

$ErrorActionPreference = 'Stop'

# Logging only. Importing Sentinel.Common keeps the ADO / GitHub / local
# output branching in one place (Write-PipelineMessage) rather than
# reimplementing it here, per the repo's PowerShell hard rules. The
# module's Az.Accounts requirement is satisfied by the runner image (the
# dependency-manifest gate imports the same module the same way).
Import-Module (Join-Path $PSScriptRoot '../Modules/Sentinel.Common/Sentinel.Common.psd1') -Force -ErrorAction Stop

# ---------------------------------------------------------------------------
# Remove-MarkdownComment
# ---------------------------------------------------------------------------
# Strips HTML comment blocks (<!-- ... -->) from a chunk of Markdown. The
# template's guidance lives in these comments; stripping them is what lets
# us tell "author wrote a real description" from "author left the template
# untouched".
function Remove-MarkdownComment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Text
    )

    # (?s) so '.' spans newlines; non-greedy so adjacent comments don't merge.
    return [regex]::Replace($Text, '(?s)<!--.*?-->', '')
}

# ---------------------------------------------------------------------------
# Get-PullRequestSection
# ---------------------------------------------------------------------------
# Splits a PR body into its level-2 (## ) sections. Returns an ordered list
# of objects { Heading; Content }. Only '## ' headings start a new section;
# deeper headings (### and beyond) stay part of the current section's
# content, so an author's sub-headings never accidentally split a section.
function Get-PullRequestSection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Body
    )

    $sections = [System.Collections.Generic.List[object]]::new()
    $heading  = $null
    $buffer   = [System.Collections.Generic.List[string]]::new()

    foreach ($line in ($Body -split '\r?\n')) {
        # Exactly two hashes followed by whitespace: '## Heading' (optionally
        # with trailing closing hashes). '### ...' does not match.
        if ($line -match '^\s{0,3}#{2}\s+(.+?)\s*#*\s*$') {
            if ($null -ne $heading) {
                $sections.Add([pscustomobject]@{
                    Heading = $heading
                    Content = ($buffer.ToArray() -join "`n")
                })
            }
            $heading = $Matches[1].Trim()
            $buffer  = [System.Collections.Generic.List[string]]::new()
        }
        elseif ($null -ne $heading) {
            $buffer.Add($line)
        }
    }

    if ($null -ne $heading) {
        $sections.Add([pscustomobject]@{
            Heading = $heading
            Content = ($buffer.ToArray() -join "`n")
        })
    }

    return $sections
}

# ---------------------------------------------------------------------------
# Test-PullRequestTemplateBody
# ---------------------------------------------------------------------------
# Pure validator. Takes the raw PR body, returns a result object
# { IsValid; Errors }. No console output and no exit - the entry-point
# below renders the result. This shape is what the Pester suite asserts on.
function Test-PullRequestTemplateBody {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Body
    )

    $errors = [System.Collections.Generic.List[string]]::new()

    # Required prose sections: heading text must be present AND, once the
    # guidance comments are stripped, hold at least $minContentChars of
    # non-whitespace text.
    $requiredProse = @(
        'Summary'
        'Why is this change needed?'
        'What does this change do?'
        'Testing'
    )
    # Section that must carry at least one ticked checkbox.
    $requiredChoice  = 'Type of change'
    $minContentChars = 10

    if ([string]::IsNullOrWhiteSpace($Body)) {
        $errors.Add('The pull request description is empty. Fill in the PR template (the summary, why the change is needed, what it does, and how it was tested).')
        return [pscustomobject]@{ IsValid = $false; Errors = $errors.ToArray() }
    }

    $sections = Get-PullRequestSection -Body $Body

    foreach ($required in $requiredProse) {
        $section = $sections | Where-Object { $_.Heading -ieq $required } | Select-Object -First 1
        if (-not $section) {
            $errors.Add("Required section '## $required' is missing. Do not delete it from the template.")
            continue
        }

        $content  = Remove-MarkdownComment -Text $section.Content
        $stripped = ($content -replace '\s', '')
        if ($stripped.Length -lt $minContentChars) {
            $errors.Add("Section '## $required' is empty. Replace the placeholder guidance with a real description.")
        }
    }

    $choice = $sections | Where-Object { $_.Heading -ieq $requiredChoice } | Select-Object -First 1
    if (-not $choice) {
        $errors.Add("Required section '## $requiredChoice' is missing. Do not delete it from the template.")
    }
    elseif ($choice.Content -notmatch '(?im)^\s*[-*]\s*\[x\]') {
        $errors.Add("No '## $requiredChoice' box is ticked. Mark at least one option with [x].")
    }

    return [pscustomobject]@{
        IsValid = ($errors.Count -eq 0)
        Errors  = $errors.ToArray()
    }
}

# ---------------------------------------------------------------------------
# Entry-point
# ---------------------------------------------------------------------------
# Not a function, so the AST-extraction test harness skips it: the Pester
# suite dot-sources only the functions above and never triggers this block
# (which would call exit).
# -Body wins whenever it was explicitly passed (even as an empty string), per
# the parameter help. Fall back to -BodyPath only when -Body was not supplied.
if ($PSBoundParameters.ContainsKey('Body')) {
    $resolvedBody = $Body
}
elseif ($BodyPath) {
    if (Test-Path -LiteralPath $BodyPath) {
        $resolvedBody = Get-Content -LiteralPath $BodyPath -Raw
    }
    else {
        Write-PipelineMessage -Level Error -Message "BodyPath not found: $BodyPath"
        exit 1
    }
}
else {
    $resolvedBody = ''
}
if ($null -eq $resolvedBody) { $resolvedBody = '' }

$result = Test-PullRequestTemplateBody -Body $resolvedBody

if ($result.IsValid) {
    Write-PipelineMessage -Level Success -Message 'PR template validation passed.'
    exit 0
}

Write-PipelineMessage -Level Section -Message 'PR template validation failed. Fix the description and the check re-runs when you save it.'

# Emit each failure as a GitHub workflow annotation when running in Actions
# (Write-PipelineMessage only knows ADO / local), otherwise a plain bullet.
# This keeps the annotation support the shared helper lacks without
# duplicating its ADO / local branching.
$inGitHub = $env:GITHUB_ACTIONS -eq 'true'
foreach ($failure in $result.Errors) {
    if ($inGitHub) {
        Write-Host "::error::$failure"
    }
    else {
        Write-Host "  - $failure"
    }
}

# Render a compact summary on the GitHub Actions run page when available.
if ($env:GITHUB_STEP_SUMMARY) {
    $summary = [System.Collections.Generic.List[string]]::new()
    [void]$summary.Add('## PR template validation failed')
    [void]$summary.Add('')
    [void]$summary.Add('The pull request description does not satisfy `.github/PULL_REQUEST_TEMPLATE.md`. Fix the items below and the check will re-run when you save the description.')
    [void]$summary.Add('')
    foreach ($failure in $result.Errors) {
        [void]$summary.Add("- $failure")
    }
    Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value ($summary.ToArray() -join "`n")
}

exit 1

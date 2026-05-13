#
# Sentinel-As-Code/Tests/_helpers/Import-ScriptFunctions.psm1
#
# Created by noodlemctwoodle on 29/04/2026.
#

<#
.SYNOPSIS
    Test-suite helper that AST-extracts every top-level function from a
    PowerShell script file and dot-sources just those into the caller's
    scope, without running the script's `param` block, `#Requires`
    directive, or `Main` entry-point.

.DESCRIPTION
    The Sentinel-As-Code deploy scripts (Deploy-CustomContent.ps1,
    Deploy-SentinelContentHub.ps1, etc.) all run authenticated Azure
    operations as their entry-point. Pester suites can't dot-source those
    files directly — doing so would call Connect-AzAccount and try to
    contact Azure on every test run.

    The trick documented in Tests/Test-SentinelRuleDrift.Tests.ps1 (lines
    40-69) avoids that: parse the script via the AST, extract every
    FunctionDefinitionAst node, join their text together, and dot-source
    the result via [ScriptBlock]::Create(). The functions are now in scope
    and testable; nothing else from the script runs.

    This module wraps that pattern in a single reusable function so each
    test suite stops carrying its own copy.

.NOTES
    Used by every Tests/Test-{Script}.Tests.ps1 file. A regression in
    Import-ScriptFunctions affects all of them at once, so the helper
    itself ships with its own self-test in
    Tests/Test-ImportScriptFunctions.Tests.ps1.

    Author:         noodlemctwoodle
    Version:        1.0.0
    Last Updated:   2026-04-29
    Repository:     Sentinel-As-Code
    Requires:       PowerShell 7.2+
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Import-ScriptFunctions {
<#
.SYNOPSIS
    Extracts top-level function definitions from a PowerShell script and
    dot-sources them into the caller's session.

.DESCRIPTION
    Parses the script's AST and locates every `FunctionDefinitionAst`
    node at the top level (no nested-function recursion — that's
    intentional; the helper only exposes the public function surface).
    Concatenates the function text and dot-sources via
    [ScriptBlock]::Create() in the CALLER's scope.

    This deliberately does NOT run the script's `param` block, `#Requires`
    directives, or any top-level statements (e.g. `Invoke-Main`). The
    caller is responsible for setting up any module imports
    (powershell-yaml, etc.) and any script-scoped constants the extracted
    functions reference.

.PARAMETER Path
    Absolute path to the source PowerShell script to extract functions
    from. The file must parse cleanly — parser errors cause this helper
    to throw with the parser's diagnostic text.

.OUTPUTS
    None. Functions are dot-sourced into the caller's scope as a
    side-effect.

.EXAMPLE
    BeforeAll {
        Import-Module "$PSScriptRoot/_helpers/Import-ScriptFunctions.psm1"
        Import-ScriptFunctions -Path "$PSScriptRoot/../Scripts/Deploy-CustomContent.ps1"
        # Functions like Get-PrioritizedFiles, Test-ContentDependencies
        # are now callable in this Describe block.
    }

.EXAMPLE
    # With a script-scoped constant the extracted functions reference
    BeforeAll {
        Import-Module "$PSScriptRoot/_helpers/Import-ScriptFunctions.psm1"
        $script:SentinelApiVersion = '2025-09-01'
        Import-ScriptFunctions -Path "$PSScriptRoot/../Scripts/Test-SentinelRuleDrift.ps1"
    }
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        throw "Import-ScriptFunctions: file not found at '$Path'"
    }

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $Path,
        [ref]$tokens,
        [ref]$errors
    )

    if ($errors -and $errors.Count -gt 0) {
        $errorList = ($errors | ForEach-Object { $_.Message }) -join '; '
        throw "Import-ScriptFunctions: parser errors in '$Path': $errorList"
    }

    # FindAll($predicate, $searchNestedScriptBlocks=$false) returns only
    # the top-level function definitions (the script's public surface),
    # not anonymous nested functions defined inside other functions. That
    # matches what test suites want to exercise.
    $funcs = $ast.FindAll(
        { param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] },
        $false
    )

    if (-not $funcs -or $funcs.Count -eq 0) {
        # Not necessarily an error — some scripts are pure orchestration
        # with no extractable functions. Caller can decide whether to
        # complain or shrug.
        Write-Verbose "Import-ScriptFunctions: no top-level functions found in '$Path'"
        return
    }

    $src = ($funcs | ForEach-Object { $_.Extent.Text }) -join "`n`n"

    # Dot-source into the CALLER's session-state, not this module's. The
    # explicit `2` skips the module scope and this function's scope so
    # the functions land where the BeforeAll block expects them.
    $callerSessionState = $PSCmdlet.SessionState
    $scriptBlock = [ScriptBlock]::Create($src)

    # InvokeWithContext runs the script block in the caller's session, so
    # function definitions land where the caller expects.
    $callerSessionState.InvokeCommand.InvokeScript(
        $callerSessionState,
        $scriptBlock,
        @()
    )
}

Export-ModuleMember -Function Import-ScriptFunctions

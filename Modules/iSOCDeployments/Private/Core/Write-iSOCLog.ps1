#Requires -Version 7.2

<#
.SYNOPSIS
    Logging for every iSOCDeployments command.

.DESCRIPTION
    Replaces Write-PipelineMessage from Modules/Sentinel.Common. The levels
    and the local console output are the same; GitHub Actions now gets its
    own warning and error annotations instead of plain text (MIGRATION.md
    edit E1).

.NOTES
    File:         Modules/iSOCDeployments/Private/Core/Write-iSOCLog.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-23
    Version:      0.1.0
    Last Updated: 2026-10-23
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Write-iSOCLog {
    <#
    .SYNOPSIS
        Write one line in the form the host running the module understands.

    .DESCRIPTION
        Azure DevOps gets its ##[warning], ##[error] and ##[section] logging
        commands and GitHub Actions its ::warning:: and ::error:: workflow
        commands, so warnings and errors are annotated on the run. A local
        console gets coloured text, warnings on the warning stream and errors
        on the error stream without stopping the caller. Debug lines go to
        the verbose stream everywhere.

    .PARAMETER Message
        The text to write. May be empty, for a blank line.

    .PARAMETER Level
        Info (default), Warning, Error, Section, Success or Debug.

    .EXAMPLE
        Write-iSOCLog 'Deploying analytics rules...' -Level Section
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'The logger is the one place the module writes to the console; pipeline logging commands must reach the host stream.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowEmptyString()]
        [string] $Message,

        [ValidateSet('Info', 'Warning', 'Error', 'Section', 'Success', 'Debug')]
        [string] $Level = 'Info'
    )

    $pipelineHost = Get-iSOCPipelineHost
    # GitHub reads a workflow command up to the end of the line, so the
    # characters that would end or corrupt it are escaped as it documents.
    $github = $Message.Replace('%', '%25').Replace("`r", '%0D').Replace("`n", '%0A')

    switch ($Level) {
        'Info' {
            Write-Host $Message
        }
        'Warning' {
            switch ($pipelineHost) {
                'AzureDevOps' { Write-Host "##[warning]$Message" }
                'GitHubActions' { Write-Host "::warning::$github" }
                default { Write-Warning $Message }
            }
        }
        'Error' {
            switch ($pipelineHost) {
                'AzureDevOps' { Write-Host "##[error]$Message" }
                'GitHubActions' { Write-Host "::error::$github" }
                default { Write-Error $Message -ErrorAction Continue }
            }
        }
        'Section' {
            if ($pipelineHost -eq 'AzureDevOps') { Write-Host "##[section]$Message" }
            else { Write-Host "`n$Message" -ForegroundColor Cyan }
        }
        'Success' {
            if ($pipelineHost -eq 'Local') { Write-Host $Message -ForegroundColor Green }
            else { Write-Host $Message }
        }
        'Debug' {
            Write-Verbose $Message
        }
    }
}

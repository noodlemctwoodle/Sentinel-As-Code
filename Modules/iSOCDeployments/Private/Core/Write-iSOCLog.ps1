#Requires -Version 7.2

<#
.SYNOPSIS
    Logging for every iSOCDeployments command.

.DESCRIPTION
    Replaces Write-PipelineMessage from Modules/Sentinel.Common. The levels
    and the local console output are the same; GitHub Actions now gets its
    own warning and error annotations instead of plain text (MIGRATION.md
    edit E1), and text in a message that a pipeline would read as one of
    its commands is broken up first (edit E45).

.NOTES
    File:         Modules/iSOCDeployments/Private/Core/Write-iSOCLog.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-23
    Version:      0.2.0
    Last Updated: 2026-11-05
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

        A message often carries text the module did not write: rule and
        workbook names set in the portal, Content Hub template names, names
        read from content files. So nothing in it may reach a pipeline as a
        command. The Azure DevOps agent acts on ##vso[ anywhere in a line
        (task.setvariable, task.prependpath and the rest), the GitHub runner
        on ##[ anywhere in a line and on a line that starts with :: once its
        whitespace is trimmed. A space breaks each: ##vso[ is written
        '# #vso[', ##[ '# #[', and a line starting :: ': :'. This is done on
        every host, because a pipeline the module does not recognise still
        reads the commands, and before the GitHub escaping below. The
        module's own ##[warning], ##[error], ##[section], ::warning:: and
        ::error:: prefixes are added after it.

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

    # Both pipeline agents split output into lines at CR, LF or CRLF, so a
    # line can start after either character.
    $text = [regex]::Replace($Message, '##(?=(?:vso)?\[)', '# #', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $text = [regex]::Replace($text, '(?<=^|[\r\n])([^\S\r\n]*)::', '$1: :')

    # GitHub reads a workflow command up to the end of the line, so the
    # characters that would end or corrupt it are escaped as it documents.
    $github = $text.Replace('%', '%25').Replace("`r", '%0D').Replace("`n", '%0A')

    switch ($Level) {
        'Info' {
            Write-Host $text
        }
        'Warning' {
            switch ($pipelineHost) {
                'AzureDevOps' { Write-Host "##[warning]$text" }
                'GitHubActions' { Write-Host "::warning::$github" }
                default { Write-Warning $text }
            }
        }
        'Error' {
            switch ($pipelineHost) {
                'AzureDevOps' { Write-Host "##[error]$text" }
                'GitHubActions' { Write-Host "::error::$github" }
                default { Write-Error $text -ErrorAction Continue }
            }
        }
        'Section' {
            if ($pipelineHost -eq 'AzureDevOps') { Write-Host "##[section]$text" }
            else { Write-Host "`n$text" -ForegroundColor Cyan }
        }
        'Success' {
            if ($pipelineHost -eq 'Local') { Write-Host $text -ForegroundColor Green }
            else { Write-Host $text }
        }
        'Debug' {
            Write-Verbose $text
        }
    }
}

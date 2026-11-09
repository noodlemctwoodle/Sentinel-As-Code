#Requires -Version 7.6

<#
.SYNOPSIS
    Run git.

.DESCRIPTION
    The only place the module runs git (Module.Tests.ps1), so a test can
    stand it in.

.NOTES
    File:         Modules/iSOCDeployments/Private/Git/Invoke-iSOCGit.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Invoke-iSOCGit {
    <#
    .SYNOPSIS
        Run git with the arguments given, and return its exit code and
        output.

    .DESCRIPTION
        Standard error is folded into the output, so a failure says why,
        unless -NoStandardError leaves it out (for output that is a list of
        paths). A non-zero exit throws, naming the git command and its
        output, unless -AllowFailure is given.

    .PARAMETER ArgumentList
        The arguments, such as clone, --depth, 1.

    .PARAMETER AllowFailure
        Return a non-zero exit code instead of throwing.

    .PARAMETER NoStandardError
        Leave standard error out of the output.

    .OUTPUTS
        [pscustomobject] ExitCode and Output (the lines).

    .EXAMPLE
        (Invoke-iSOCGit -ArgumentList '-C', $path, 'rev-parse', 'HEAD').Output
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string[]] $ArgumentList,

        [switch] $AllowFailure,

        [switch] $NoStandardError
    )

    $output = if ($NoStandardError) { & git @ArgumentList 2>$null } else { & git @ArgumentList 2>&1 }
    $code = $LASTEXITCODE
    $lines = @($output | ForEach-Object { "$_" })
    if ($code -ne 0 -and -not $AllowFailure) { throw "git $($ArgumentList[0]) exited with code $code. $($lines -join ' ')" }
    [pscustomobject]@{ ExitCode = $code; Output = $lines }
}

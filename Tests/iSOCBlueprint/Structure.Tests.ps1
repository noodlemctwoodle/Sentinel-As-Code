#Requires -Version 7.6
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests that keep the iSOCBlueprint module's PowerShell files small.

.DESCRIPTION
    A module file holds one concern and stays within 300 lines, as in
    iSOCDeployments. Every PowerShell file under the module is held to it; a
    file that grows past the limit fails and is split up.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCBlueprint/Structure.Tests.ps1

    Checks every PowerShell file under Modules/iSOCBlueprint against the
    limit.

.NOTES
    File:         Tests/iSOCBlueprint/Structure.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.2.0
    Last Updated: 2026-11-16
    Requires:     PowerShell 7.6+, Pester 5+
#>

BeforeDiscovery {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $moduleRoot = Join-Path $repoRoot 'Modules/iSOCBlueprint'
    $limit = 300
    $files = @(
        Get-ChildItem -LiteralPath $moduleRoot -Filter '*.ps1' -File -Recurse |
            Where-Object { $_.FullName -notmatch '[\\/]WebParts[\\/]' } |
            ForEach-Object {
                $relative = [System.IO.Path]::GetRelativePath($moduleRoot, $_.FullName).Replace('\', '/')
                @{ Path = $relative; Lines = @(Get-Content -LiteralPath $_.FullName).Count; Limit = $limit }
            }
    )
}

Describe 'Module file size' {
    It '<Path> is <Lines> lines, within the <Limit> line limit' -ForEach $files {
        $Lines | Should -BeLessOrEqual $Limit
    }
}

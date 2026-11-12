#Requires -Version 7.6
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests that keep the iSOCBlueprint module's PowerShell files small.

.DESCRIPTION
    A module file holds one concern and stays within 300 lines, as in
    iSOCDeployments. The engine scripts that predate that rule are listed
    below until each is split up; the list only ever shrinks. A file on it
    that now fits must be taken off, and a file not on it that grows past the
    limit fails.

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
    Version:      0.1.0
    Last Updated: 2026-11-12
    Requires:     PowerShell 7.6+, Pester 5+
#>

BeforeDiscovery {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $moduleRoot = Join-Path $repoRoot 'Modules/iSOCBlueprint'
    $limit = 300
    $legacy = @(
        'Engine/Report/Convert-MarkdownToWord.ps1'
        'Engine/SharePoint/Private/ConvertTo-SharePointPageSegments.ps1'
        'Engine/Private/ConvertFrom-BlueprintMermaid.ps1'
        'Engine/SharePoint/Publish-SentinelDocsSite.ps1'
        'Engine/Private/ConvertTo-BlueprintSection.ps1'
        'Engine/Private/Get-SentinelCostEstimate.ps1'
        'Engine/Private/Write-CaptureSummary.ps1'
        'Engine/SharePoint/Private/Get-SacSyncPlan.ps1'
        'Public/New-iSOCBlueprint.ps1'
        'Engine/Private/Format-BlueprintText.ps1'
        'Engine/Private/Get-WhatsNew.ps1'
    )
    $files = @(
        Get-ChildItem -LiteralPath $moduleRoot -Filter '*.ps1' -File -Recurse |
            Where-Object { $_.FullName -notmatch '[\\/]WebParts[\\/]' } |
            ForEach-Object {
                $relative = [System.IO.Path]::GetRelativePath($moduleRoot, $_.FullName).Replace('\', '/')
                @{ Path = $relative; Lines = @(Get-Content -LiteralPath $_.FullName).Count; Limit = $limit; IsLegacy = $legacy -contains $relative }
            }
    )
    $current = @($files | Where-Object { -not $_.IsLegacy })
    $listed = @($files | Where-Object { $_.IsLegacy })
    $missing = @($legacy | Where-Object { $_ -notin $files.Path } | ForEach-Object { @{ Path = $_ } })
}

Describe 'Module file size' {
    It '<Path> is <Lines> lines, within the <Limit> line limit' -ForEach $current {
        $Lines | Should -BeLessOrEqual $Limit
    }

    It 'lists <Path> as over the limit only while it still is' -ForEach $listed {
        $Lines | Should -BeGreaterThan $Limit -Because 'it now fits, so take it off the legacy list in this file'
    }

    It 'lists <Path> only while the file exists' -ForEach $missing {
        $Path | Should -BeNullOrEmpty -Because 'the file is gone or renamed, so take it off the legacy list in this file'
    }
}

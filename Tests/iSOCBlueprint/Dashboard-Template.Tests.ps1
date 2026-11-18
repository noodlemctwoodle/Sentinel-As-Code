#Requires -Version 7.6
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for the dashboard template: the small parts it is kept in
    and the function that joins them.

.DESCRIPTION
    The dashboard is one HTML page, kept as numbered parts under
    Resources/SharePoint/templates/dashboard (head, style, body, script, end)
    and joined by Get-SiteDashboardTemplate when the site is built. These
    tests hold every part to 300 lines, check that the joined page is whole
    (one style block, balanced script blocks, each placeholder once), and
    that the parts are joined in path order whatever order the file system
    lists them in.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCBlueprint/Dashboard-Template.Tests.ps1

    Checks the template's parts and the function that joins them.

.NOTES
    File:         Tests/iSOCBlueprint/Dashboard-Template.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.1.2
    Last Updated: 2026-11-16
    Requires:     PowerShell 7.6+, Pester 5+
#>

BeforeDiscovery {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $root = Join-Path $repoRoot 'Modules/iSOCBlueprint/Resources/SharePoint/templates/dashboard'
    $parts = @(
        Get-ChildItem -LiteralPath $root -File -Recurse | Where-Object { $_.Extension -in '.html', '.css', '.js' } | ForEach-Object {
            @{
                Path = [System.IO.Path]::GetRelativePath($root, $_.FullName).Replace('\', '/')
                Lines = @(Get-Content -LiteralPath $_.FullName).Count
                Limit = 300
            }
        }
    )
}

BeforeAll {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:root = Join-Path $repoRoot 'Modules/iSOCBlueprint/Resources/SharePoint/templates/dashboard'
    . (Join-Path $repoRoot 'Modules/iSOCBlueprint/Private/Site/Helpers/Output/Get-SiteDashboardTemplate.ps1')
    $script:page = Get-SiteDashboardTemplate -Root $script:root
}

Describe 'Dashboard template parts' {
    It '<Path> is <Lines> lines, within the <Limit> line limit' -ForEach $parts {
        $Lines | Should -BeLessOrEqual $Limit
    }

    It '<Path> is an .html, .css or .js part named with its order' -ForEach $parts {
        $Path | Should -Match '^(\d\d-[a-z0-9-]+\.(html|css|js)|\d\d-[a-z0-9-]+/[a-z0-9-]+\.(html|css|js))$'
    }
}

Describe 'Get-SiteDashboardTemplate' {
    It 'joins the parts into one whole page' {
        $script:page | Should -Match '^<!DOCTYPE html>'
        $script:page | Should -Match '</html>\n$'
        ([regex]::Matches($script:page, '<style>')).Count | Should -Be 1
        ([regex]::Matches($script:page, '</style>')).Count | Should -Be 1
        ([regex]::Matches($script:page, '<script')).Count | Should -Be ([regex]::Matches($script:page, '</script>')).Count
    }

    It 'keeps each placeholder the site build fills in once: <Token>' -ForEach @(
        @{ Token = '__TITLE__' }, @{ Token = '/*__MODEL__*/null' }, @{ Token = '/*__SAC_CHARTS__*/' }
    ) {
        ([regex]::Matches($script:page, [regex]::Escape($Token))).Count | Should -Be 1
    }

    It 'joins the parts in path order and reads only .html, .css and .js files' {
        $dir = Join-Path $TestDrive 'template'
        New-Item -ItemType Directory -Path (Join-Path $dir '02-dir') -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $dir '10-last.html'), "D`n")
        [System.IO.File]::WriteAllText((Join-Path $dir '02-dir/02-c.js'), "C`n")
        [System.IO.File]::WriteAllText((Join-Path $dir '02-dir/01-b.css'), "B`n")
        [System.IO.File]::WriteAllText((Join-Path $dir '01-a.html'), "A`n")
        [System.IO.File]::WriteAllText((Join-Path $dir 'README.md'), "ignored`n")
        Get-SiteDashboardTemplate -Root $dir | Should -BeExactly "A`nB`nC`nD`n"
    }

    It 'refuses a folder that is missing or holds no parts' {
        { Get-SiteDashboardTemplate -Root (Join-Path $TestDrive 'nothing') } | Should -Throw '*is missing*'
        $empty = Join-Path $TestDrive 'empty'
        New-Item -ItemType Directory -Path $empty | Out-Null
        { Get-SiteDashboardTemplate -Root $empty } | Should -Throw '*holds no parts*'
    }
}

#Requires -Version 7.6
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for the Word report's Markdown rewrites.

.DESCRIPTION
    Export-iSOCBlueprintWord runs pandoc when it is invoked, so these
    tests load only the Word helper functions, through the parser, and drive them on
    small Markdown strings. They pin how status words are coloured now that
    the Blueprint pages carry plain words instead of coloured emoji: a cell
    is coloured only under a status column, and the severity on a finding
    card and a finding bullet keeps its colour.

.NOTES
    File:         Tests/iSOCBlueprint/Convert-MarkdownToWord.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-13
    Version:      0.1.4
    Last Updated: 2026-11-16
    Requires:     PowerShell 7.6+, Pester 5+
#>

BeforeAll {
    $helpers = Join-Path $PSScriptRoot '../../Modules/iSOCBlueprint/Private/Word/Helpers/Markdown'
    foreach ($name in 'Convert-StatusWord', 'Convert-FindingBullet') {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $helpers "$name.ps1"), [ref]$null, [ref]$null)
        foreach ($fn in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq $name }, $true)) {
            . ([scriptblock]::Create($fn.Extent.Text))
        }
    }
    function Invoke-Status([string]$Text) {
        <#
        .SYNOPSIS
            Runs the status word converter and returns the text with the replacement count.
        .PARAMETER Text
            The Markdown to convert.
        #>
        $count = [ref]0
        [pscustomobject]@{ Text = (Convert-StatusWord -Text $Text -Count $count); Count = $count.Value }
    }
}

Describe 'Convert-StatusWord' {

    It 'colours the words in a Coverage column' {
        $r = Invoke-Status "| Tactic | Coverage |`n|---|---|`n| Recon | None |`n| Exec | Covered |`n| Persist | Thin |"
        $r.Text | Should -Match '\| Recon \| \[None\]\{custom-style="SevCritical"\} \|'
        $r.Text | Should -Match '\[Covered\]\{custom-style="SevLow"\}'
        $r.Text | Should -Match '\[Thin\]\{custom-style="SevWarning"\}'
        $r.Count | Should -Be 3
    }

    It 'leaves the same word alone in any other column' {
        $r = Invoke-Status "| Name | Note |`n|---|---|`n| x | None |"
        $r.Text | Should -Match '\| x \| None \|'
        $r.Count | Should -Be 0
    }

    It 'colours criterion status, severity and rating columns' {
        $r = Invoke-Status "| Criterion | Status | Severity | Rating |`n|---|---|---|---|`n| A | Gap | Warning | Strong |`n| B | Met | Info | Weak |"
        $r.Text | Should -Match '\[Gap\]\{custom-style="SevCritical"\}'
        $r.Text | Should -Match '\[Met\]\{custom-style="SevLow"\}'
        $r.Text | Should -Match '\[Warning\]\{custom-style="SevWarning"\}'
        $r.Text | Should -Match '\[Info\]\{custom-style="SevInfo"\}'
        $r.Text | Should -Match '\[Strong\]\{custom-style="SevLow"\}'
        $r.Text | Should -Match '\[Weak\]\{custom-style="SevWarning"\}'
    }

    It 'keeps an escaped pipe inside a cell' {
        $r = Invoke-Status "| Criterion | Status |`n|---|---|`n| A \| B | Gap |"
        $r.Text | Should -Match '\| A \\\| B \| \[Gap\]'
    }

    It 'stops at the end of the table' {
        $r = Invoke-Status "| Severity |`n|---|`n| Warning |`n`nWarning in prose stays plain."
        $r.Text | Should -Match 'Warning in prose stays plain\.'
        $r.Count | Should -Be 1
    }

    It 'colours the severity on a finding card' {
        $r = Invoke-Status '**Severity:** Critical  ·  **Category:** Cost'
        $r.Text | Should -Match '\*\*Severity:\*\* \[Critical\]\{custom-style="SevCritical"\}'
    }
}

Describe 'Convert-FindingBullet' {

    It 'colours a plain severity word on a finding bullet' {
        $count = [ref]0
        $out = Convert-FindingBullet -Text '- **Warning** [SAC-LOG-22](90-gap-analysis.md#sac-log-22) SecurityEvent duplicates - two agents' -TitleMap @{} `
            -Count $count
        $out | Should -Match '\[Warning\]\{custom-style="SevWarning"\}'
        $count.Value | Should -Be 1
    }
}

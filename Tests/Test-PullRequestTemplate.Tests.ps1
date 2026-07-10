#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester 5 tests for the pure functions in
    Tools/Test-PullRequestTemplate.ps1.

.DESCRIPTION
    Covers the three functions that own the PR-template parsing and
    validation:

      - Remove-MarkdownComment
      - Get-PullRequestSection
      - Test-PullRequestTemplateBody

    The harness AST-extracts those functions (via the shared
    Import-ScriptFunctions helper) and dot-sources them, so the script's
    entry-point (which calls exit) never runs.
#>

BeforeAll {
    $repoRoot   = Split-Path -Parent $PSScriptRoot
    $scriptPath = Join-Path $repoRoot 'Tools/Test-PullRequestTemplate.ps1'

    Import-Module (Join-Path $PSScriptRoot '_helpers/Import-ScriptFunctions.psm1') -Force -ErrorAction Stop
    Import-ScriptFunctions -Path $scriptPath

    # A description that satisfies every rule. Individual tests mutate a copy
    # to exercise the failure paths.
    $script:ValidBody = @'
## Summary

Adds a Copilot mass sensitive resource access detection rule.

## Why is this change needed?

There is no detection today for large-scale Copilot data access, leaving a visibility gap for exfiltration.

## What does this change do?

Adds the analytical rule YAML and regenerates the dependency manifest so the new rule is tracked.

## What does this fix or affect?

Closes the Copilot exfiltration visibility gap. No behavioural change to existing rules.

## Type of change

- [x] feat - new capability
- [ ] fix - bug fix

## Testing

Ran ./Tools/Invoke-PRValidation.ps1 locally; every Pester suite passed.
'@
}

Describe 'Remove-MarkdownComment' {
    It 'strips a single inline comment' {
        Remove-MarkdownComment -Text 'before <!-- hidden --> after' | Should -Be 'before  after'
    }

    It 'strips a multi-line comment' {
        $text = "keep`n<!-- line one`nline two -->`nkeep too"
        $result = Remove-MarkdownComment -Text $text
        $result | Should -Match 'keep too'
        $result | Should -Not -Match 'line one'
    }

    It 'leaves comment-free text untouched' {
        Remove-MarkdownComment -Text 'plain text' | Should -Be 'plain text'
    }

    It 'reduces a comment-only string to whitespace' {
        (Remove-MarkdownComment -Text '<!-- guidance only -->').Trim() | Should -BeNullOrEmpty
    }
}

Describe 'Get-PullRequestSection' {
    It 'splits on level-2 headings only' {
        $body = "## A`nalpha`n### sub-heading`nbeta`n## B`ngamma"
        $sections = @(Get-PullRequestSection -Body $body)
        $sections.Count            | Should -Be 2
        $sections[0].Heading       | Should -Be 'A'
        $sections[1].Heading       | Should -Be 'B'
    }

    It 'keeps deeper headings inside the parent section content' {
        $body = "## A`nalpha`n### sub-heading`nbeta"
        $sections = @(Get-PullRequestSection -Body $body)
        $sections[0].Content | Should -Match 'sub-heading'
        $sections[0].Content | Should -Match 'beta'
    }

    It 'trims trailing closing hashes from the heading' {
        $body = "## Heading ##`nbody"
        (Get-PullRequestSection -Body $body)[0].Heading | Should -Be 'Heading'
    }

    It 'ignores content before the first heading' {
        $body = "leading preamble`n## Real`nbody"
        $sections = @(Get-PullRequestSection -Body $body)
        $sections.Count      | Should -Be 1
        $sections[0].Heading | Should -Be 'Real'
    }
}

Describe 'Test-PullRequestTemplateBody' {
    Context 'a well-formed description' {
        It 'passes with no errors' {
            $result = Test-PullRequestTemplateBody -Body $script:ValidBody
            $result.IsValid      | Should -BeTrue
            $result.Errors.Count | Should -Be 0
        }

        It 'accepts an uppercase [X] tick' {
            $body   = $script:ValidBody -replace '- \[x\] feat', '- [X] feat'
            $result = Test-PullRequestTemplateBody -Body $body
            $result.IsValid | Should -BeTrue
        }
    }

    Context 'an empty description' {
        It 'fails on a completely empty body' {
            $result = Test-PullRequestTemplateBody -Body ''
            $result.IsValid | Should -BeFalse
            ($result.Errors -join "`n") | Should -Match 'empty'
        }

        It 'fails on a whitespace-only body' {
            $result = Test-PullRequestTemplateBody -Body "   `n`t  "
            $result.IsValid | Should -BeFalse
        }
    }

    Context 'a missing required section' {
        It 'fails when "Why is this change needed?" is removed' {
            $body   = $script:ValidBody -replace '(?s)## Why is this change needed\?.*?(?=## What does this change do\?)', ''
            $result = Test-PullRequestTemplateBody -Body $body
            $result.IsValid | Should -BeFalse
            ($result.Errors -join "`n") | Should -Match 'Why is this change needed'
        }
    }

    Context 'a section left as the placeholder' {
        It 'fails when Summary holds only a guidance comment' {
            $body   = $script:ValidBody -replace 'Adds a Copilot mass sensitive resource access detection rule\.', '<!-- one or two sentences -->'
            $result = Test-PullRequestTemplateBody -Body $body
            $result.IsValid | Should -BeFalse
            ($result.Errors -join "`n") | Should -Match "Section '## Summary' is empty"
        }
    }

    Context 'no type-of-change box ticked' {
        It 'fails when every box is unchecked' {
            $body   = $script:ValidBody -replace '- \[x\] feat - new capability', '- [ ] feat - new capability'
            $result = Test-PullRequestTemplateBody -Body $body
            $result.IsValid | Should -BeFalse
            ($result.Errors -join "`n") | Should -Match 'box is ticked'
        }
    }

    Context 'multiple problems at once' {
        It 'reports one error per failing rule' {
            $body   = "## Summary`n`n<!-- nothing -->`n`n## Type of change`n`n- [ ] feat - new capability"
            $result = Test-PullRequestTemplateBody -Body $body
            $result.IsValid      | Should -BeFalse
            $result.Errors.Count | Should -BeGreaterThan 1
        }
    }
}

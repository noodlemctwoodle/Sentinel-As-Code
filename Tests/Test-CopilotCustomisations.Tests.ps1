#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester 5 tests for the GitHub Copilot customisation set under
    .github/agents, .github/instructions, .github/prompts, and the
    repo-wide .github/copilot-instructions.md + AGENTS.md.

.DESCRIPTION
    Validates the agent set the way the .agent.md / .instructions.md /
    .prompt.md formats are documented in the latest GitHub Copilot
    standards (April 2026):

      - YAML frontmatter parses cleanly.
      - Required frontmatter keys are present.
      - File extensions match the canonical convention
        (`.agent.md`, `.instructions.md`, `.prompt.md`).
      - Agents follow the repo's display-name prefix convention
        (`Sentinel-As-Code:`).
      - applyTo globs in path-scoped instructions look syntactically
        valid.
      - Cross-references between Copilot files and Docs / scripts /
        modules in the rest of the repo resolve to real targets.

    Generates per-file It blocks via -ForEach so per-file failures
    surface directly in the PR check UI.

.NOTES
    Run as part of the repo-wide Pester gate
    (Scripts/Invoke-PRValidation.ps1) on every PR via the
    `validate` job in .github/workflows/pr-validation.yml.
#>

BeforeDiscovery {
    $script:repoRoot      = Split-Path -Parent $PSScriptRoot

    $script:agentFiles        = @(Get-ChildItem -Path "$repoRoot/.github/agents"       -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '*.agent.md' })
    $script:instructionFiles  = @(Get-ChildItem -Path "$repoRoot/.github/instructions" -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '*.instructions.md' })
    $script:promptFiles       = @(Get-ChildItem -Path "$repoRoot/.github/prompts"      -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '*.prompt.md' })

    # Stray files in those folders that don't match the expected
    # extension — typically a sign of a half-renamed or
    # accidentally-committed file. Capture for a separate test.
    $script:strayFiles = @(
        Get-ChildItem -Path "$repoRoot/.github/agents", "$repoRoot/.github/instructions", "$repoRoot/.github/prompts" -Recurse -File -ErrorAction SilentlyContinue
            | Where-Object { $_.Name -notmatch '\.(agent|instructions|prompt)\.md$' }
    )
}

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot

    if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
        Install-Module -Name powershell-yaml -Force -Scope CurrentUser -AllowClobber | Out-Null
    }
    Import-Module powershell-yaml -ErrorAction Stop

    function Get-Frontmatter {
        param([Parameter(Mandatory)] [string] $Path)

        $content = Get-Content -Path $Path -Raw
        if ($content -notmatch '(?ms)^---\s*\r?\n(.*?)\r?\n---\s*\r?\n') {
            return $null
        }
        $yamlBlock = $Matches[1]
        try {
            return ConvertFrom-Yaml -Yaml $yamlBlock
        }
        catch {
            return $null
        }
    }
}

# ============================================================================
# Repo-wide instructions
# ============================================================================

Describe 'Repo-wide Copilot instructions' {

    It '.github/copilot-instructions.md exists' {
        Test-Path "$repoRoot/.github/copilot-instructions.md" | Should -BeTrue
    }

    It 'AGENTS.md exists at repo root' {
        Test-Path "$repoRoot/AGENTS.md" | Should -BeTrue
    }

    It '.github/copilot-instructions.md is non-empty' {
        (Get-Item "$repoRoot/.github/copilot-instructions.md").Length | Should -BeGreaterThan 0
    }

    It 'AGENTS.md is non-empty' {
        (Get-Item "$repoRoot/AGENTS.md").Length | Should -BeGreaterThan 0
    }
}

# ============================================================================
# Agent files (.github/agents/*.agent.md)
# ============================================================================

Describe 'Custom agents (.github/agents/)' {

    It 'has at least one .agent.md file' {
        $agentFiles.Count | Should -BeGreaterThan 0
    }

    Context 'per-file shape' -ForEach $agentFiles {

        BeforeAll {
            $script:fm = Get-Frontmatter -Path $_.FullName
        }

        It 'parses frontmatter cleanly — <_.Name>' {
            $fm | Should -Not -BeNullOrEmpty
        }

        It 'has a non-empty description (required) — <_.Name>' {
            $fm.description | Should -Not -BeNullOrEmpty
            ([string]$fm.description).Length | Should -BeGreaterThan 0
        }

        It 'name follows the Sentinel-As-Code: <Role> convention — <_.Name>' {
            $fm.name | Should -Not -BeNullOrEmpty
            $fm.name | Should -Match '^Sentinel-As-Code:\s+\S'
        }

        It 'tools is a list when present — <_.Name>' {
            if ($fm.PSObject.Properties.Name -contains 'tools' -or ($fm -is [System.Collections.IDictionary] -and $fm.Contains('tools'))) {
                $tools = $fm['tools']
                # YAML inline ['a', 'b'] is parsed as Object[] / List
                $tools | Should -Not -BeNullOrEmpty
                @($tools).Count | Should -BeGreaterThan 0
            }
        }
    }
}

# ============================================================================
# Path-scoped instructions (.github/instructions/*.instructions.md)
# ============================================================================

Describe 'Path-scoped instructions (.github/instructions/)' {

    It 'has at least one .instructions.md file' {
        $instructionFiles.Count | Should -BeGreaterThan 0
    }

    Context 'per-file shape' -ForEach $instructionFiles {

        BeforeAll {
            $script:fm = Get-Frontmatter -Path $_.FullName
        }

        It 'parses frontmatter cleanly — <_.Name>' {
            $fm | Should -Not -BeNullOrEmpty
        }

        It 'has applyTo glob (the whole point of path-scoped) — <_.Name>' {
            $fm.applyTo | Should -Not -BeNullOrEmpty
        }

        It 'applyTo is comma-separated globs (no leading slash) — <_.Name>' {
            $patterns = ([string]$fm.applyTo).Split(',') | ForEach-Object { $_.Trim() }
            foreach ($p in $patterns) {
                $p | Should -Not -Match '^/' -Because 'applyTo globs are repo-relative; should not start with /'
                $p | Should -Not -Match '^\./' -Because 'applyTo globs are repo-relative; should not start with ./'
            }
        }
    }
}

# ============================================================================
# Prompts (.github/prompts/*.prompt.md)
# ============================================================================

Describe 'Reusable prompts (.github/prompts/)' {

    It 'has at least one .prompt.md file' {
        $promptFiles.Count | Should -BeGreaterThan 0
    }

    Context 'per-file shape' -ForEach $promptFiles {

        BeforeAll {
            $script:fm = Get-Frontmatter -Path $_.FullName
        }

        It 'parses frontmatter cleanly — <_.Name>' {
            $fm | Should -Not -BeNullOrEmpty
        }

        It 'has a non-empty description — <_.Name>' {
            $fm.description | Should -Not -BeNullOrEmpty
        }

        It 'agent value (if set) is a recognised mode — <_.Name>' {
            if ($fm.PSObject.Properties.Name -contains 'agent' -or ($fm -is [System.Collections.IDictionary] -and $fm.Contains('agent'))) {
                # Built-ins ask / agent / plan, OR a custom-agent slug.
                # We accept anything non-empty here — Copilot validates
                # at runtime — but flag obviously-malformed values.
                ([string]$fm['agent']) | Should -Not -BeNullOrEmpty
                ([string]$fm['agent']) | Should -Not -Match '\s'  # no spaces in identifier
            }
        }
    }
}

# ============================================================================
# Stray files / extension hygiene
# ============================================================================

Describe 'Folder hygiene' {

    It 'no stray files (wrong extension or naming) under .github/agents | instructions | prompts' {
        # Drop common metadata files that some tools auto-create
        $stray = @($strayFiles | Where-Object { $_.Name -notin @('.DS_Store', '.gitignore', 'README.md') })
        $stray.Count | Should -Be 0 -Because (
            "Found stray files: " + (($stray | ForEach-Object { $_.FullName.Substring($repoRoot.Length + 1) }) -join ', ')
        )
    }
}

# ============================================================================
# Cross-references — Copilot files referencing Docs / scripts / modules
# ============================================================================

Describe 'Cross-references resolve' {

    BeforeAll {
        # Build the set of every Copilot-customisation file (paths
        # relative to repo root with forward slashes).
        $script:allCopilotFiles = @()
        $script:allCopilotFiles += "$repoRoot/.github/copilot-instructions.md"
        $script:allCopilotFiles += "$repoRoot/AGENTS.md"
        $script:allCopilotFiles += $agentFiles.FullName
        $script:allCopilotFiles += $instructionFiles.FullName
        $script:allCopilotFiles += $promptFiles.FullName

        # Pull every relative-link target the customisation files
        # mention. Markdown link form: [text](relative/path[#anchor]).
        # Skip absolute http(s) URLs and bare anchors.
        $script:linkRefs = [System.Collections.Generic.List[object]]::new()
        foreach ($p in $allCopilotFiles) {
            if (-not (Test-Path $p)) { continue }
            $text = Get-Content -Path $p -Raw
            foreach ($m in [regex]::Matches($text, '\]\((?<target>[^)\s]+)\)')) {
                $target = $m.Groups['target'].Value
                if ($target -match '^(https?:|mailto:|#)') { continue }
                # Strip anchor for path resolution
                $cleanPath = ($target -split '#')[0]
                if ([string]::IsNullOrWhiteSpace($cleanPath)) { continue }
                $linkRefs.Add([pscustomobject]@{
                    Source = $p
                    Target = $cleanPath
                })
            }
        }
    }

    It 'every relative link in a Copilot file resolves to a real path' {
        $broken = @()
        foreach ($ref in $linkRefs) {
            $sourceDir = Split-Path -Parent $ref.Source
            $resolved = Join-Path $sourceDir $ref.Target
            if (-not (Test-Path $resolved)) {
                $relSource = $ref.Source.Substring($repoRoot.Length + 1) -replace '\\', '/'
                $broken += "  $relSource -> $($ref.Target)"
            }
        }

        $broken.Count | Should -Be 0 -Because (
            "Found broken cross-references:`n" + ($broken -join "`n")
        )
    }
}

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester 5 unit tests for the pure functions in
    Scripts/Deploy-CustomContent.ps1, covering dependency-graph
    initialisation, smart-deployment file ordering, and the
    content-vs-prerequisite resolver.

.DESCRIPTION
    Three deploy-time pure functions worth pinning with tests:
      - Initialize-DependencyGraph (parses dependencies.json into a
        hashtable; tolerates missing file)
      - Get-PrioritizedFiles (reorders FileInfo[] using the priority list
        from sentinel-deployment.config)
      - Test-ContentDependencies (returns Passed/Missing for a content
        item against the loaded graph + workspace state + repo state)

    The script's other functions are wrapped around Azure API calls or
    filesystem writes; those aren't unit-testable in isolation and would
    need integration tests.

    Helper-driven: imports script functions via the AST extractor in
    Tests/_helpers/Import-ScriptFunctions.psm1.

.NOTES
    Run all tests:
        Invoke-Pester -Path Tests/Test-DeployCustomContent.Tests.ps1
#>

BeforeAll {
    $repoRoot   = Split-Path -Parent $PSScriptRoot
    $scriptPath = Join-Path $repoRoot 'Scripts/Deploy-CustomContent.ps1'

    Import-Module (Join-Path $PSScriptRoot '_helpers/Import-ScriptFunctions.psm1') -Force -ErrorAction Stop
    Import-ScriptFunctions -Path $scriptPath

    # Stub Write-PipelineMessage so the imported functions can call it
    # without complaining about ADO/local detection state. Nothing the
    # tests assert on depends on its output.
    function Write-PipelineMessage {
        param([string]$Message, [string]$Level = 'Info')
        # no-op
    }
}

Describe 'Initialize-DependencyGraph' {
    BeforeEach {
        # Reset all script state the functions read. Each test sets up its
        # own fixture under $TestDrive and points $BasePath at it.
        $script:DependencyGraph    = @{}
        $script:WorkspaceTables    = @()
        $script:WorkspaceWatchlists = @()
        $script:WorkspaceFunctions = @()
        $script:InternalWatchlists = @()
        $script:InternalParsers    = @()
        $script:DeploymentConfig   = $null
    }

    It 'returns silently when dependencies.json is absent' {
        $BasePath = $TestDrive
        # No dependencies.json in TestDrive; function should treat as empty.
        { Initialize-DependencyGraph } | Should -Not -Throw
        $script:DependencyGraph.Count | Should -Be 0
    }

    It 'parses a minimal dependencies.json into the script-scope graph' {
        $BasePath = $TestDrive
        $manifest = @{
            version      = '1.0'
            description  = 'test'
            dependencies = @{
                'AnalyticalRules/Foo.yaml' = @{
                    tables     = @('TableA')
                    watchlists = @('WatchlistA')
                }
            }
        }
        $manifestJson = $manifest | ConvertTo-Json -Depth 32
        Set-Content -Path (Join-Path $BasePath 'dependencies.json') -Value $manifestJson

        Initialize-DependencyGraph

        $script:DependencyGraph.Count | Should -Be 1
        $script:DependencyGraph.ContainsKey('AnalyticalRules/Foo.yaml') | Should -BeTrue
        $entry = $script:DependencyGraph['AnalyticalRules/Foo.yaml']
        @($entry.tables) | Should -Contain 'TableA'
        @($entry.watchlists) | Should -Contain 'WatchlistA'
    }

    It 'recognises every dependency-array key (tables / watchlists / functions / externalData / playbooks)' {
        $BasePath = $TestDrive
        $manifest = @{
            version = '1.0'; description = 'test'
            dependencies = @{
                'X.yaml' = @{
                    tables       = @('T')
                    watchlists   = @('W')
                    functions    = @('F')
                    externalData = @('https://example.com/feed.json')
                    playbooks    = @('P')
                }
            }
        }
        Set-Content -Path (Join-Path $BasePath 'dependencies.json') -Value ($manifest | ConvertTo-Json -Depth 32)

        Initialize-DependencyGraph

        $entry = $script:DependencyGraph['X.yaml']
        @($entry.tables)       | Should -Contain 'T'
        @($entry.watchlists)   | Should -Contain 'W'
        @($entry.functions)    | Should -Contain 'F'
        @($entry.externalData) | Should -Contain 'https://example.com/feed.json'
        @($entry.playbooks)    | Should -Contain 'P'
    }

    It 'is tolerant of malformed JSON (logs warning, leaves graph empty)' {
        $BasePath = $TestDrive
        Set-Content -Path (Join-Path $BasePath 'dependencies.json') -Value '{ this is not valid json'

        # Function catches its own JSON-parse errors and writes a warning.
        # We assert only that it does not throw and leaves the graph empty.
        { Initialize-DependencyGraph } | Should -Not -Throw
        $script:DependencyGraph.Count | Should -Be 0
    }
}

Describe 'Get-PrioritizedFiles' {
    BeforeEach {
        $script:DeploymentConfig = $null

        $script:fakeDir = Join-Path $TestDrive 'fakeRepo'
        New-Item -ItemType Directory -Path $script:fakeDir -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:fakeDir 'AnalyticalRules') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:fakeDir 'Watchlists') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:fakeDir 'Parsers') -Force | Out-Null

        $script:fileA = New-Item -ItemType File -Path (Join-Path $script:fakeDir 'AnalyticalRules/A.yaml') -Force
        $script:fileB = New-Item -ItemType File -Path (Join-Path $script:fakeDir 'Watchlists/B.json') -Force
        $script:fileC = New-Item -ItemType File -Path (Join-Path $script:fakeDir 'Parsers/C.yaml') -Force
        $script:files = @($script:fileA, $script:fileB, $script:fileC)

        $BasePath = $script:fakeDir
    }

    It 'returns input unchanged when no DeploymentConfig is loaded' {
        $BasePath = $script:fakeDir
        $result = Get-PrioritizedFiles -Files $script:files
        @($result).Count | Should -Be 3
        @($result)[0].Name | Should -Be 'A.yaml'
        @($result)[2].Name | Should -Be 'C.yaml'
    }

    It 'returns input unchanged when DeploymentConfig has no prioritizedcontentfiles' {
        $BasePath = $script:fakeDir
        $script:DeploymentConfig = [pscustomobject]@{ otherProperty = 'value' }
        $result = Get-PrioritizedFiles -Files $script:files
        @($result).Count | Should -Be 3
    }

    It 'reorders matched files to the front, preserving relative order of the rest' {
        $BasePath = $script:fakeDir
        $script:DeploymentConfig = [pscustomobject]@{
            prioritizedcontentfiles = @('Parsers/C.yaml', 'Watchlists/')
        }
        $result = @(Get-PrioritizedFiles -Files $script:files)
        $result.Count | Should -Be 3
        # Both prefixes match: C.yaml exact, Watchlists/ prefix-matches B.json.
        # Priority files come first; A.yaml stays at the back.
        $names = $result | ForEach-Object { $_.Name }
        $names[-1] | Should -Be 'A.yaml'
        $names | Should -Contain 'B.json'
        $names | Should -Contain 'C.yaml'
    }

    It 'matches by exact path or path prefix' {
        $BasePath = $script:fakeDir
        $script:DeploymentConfig = [pscustomobject]@{
            prioritizedcontentfiles = @('Parsers/')   # prefix-only
        }
        $result = @(Get-PrioritizedFiles -Files $script:files)
        ($result[0].Name) | Should -Be 'C.yaml' -Because 'Parsers/ prefix should match Parsers/C.yaml'
    }
}

Describe 'Test-ContentDependencies' {
    BeforeEach {
        # Reset every state variable the function reads.
        $script:DependencyGraph    = @{}
        $script:WorkspaceTables    = @()
        $script:WorkspaceWatchlists = @()
        $script:WorkspaceFunctions = @()
        $script:InternalWatchlists = @()
        $script:InternalParsers    = @()

        # Use a stable fake repo root so paths normalise predictably.
        $script:fakeRoot = Join-Path $TestDrive 'fakeRepo'
        New-Item -ItemType Directory -Path $script:fakeRoot -Force | Out-Null
    }

    It 'returns Passed=true when the dependency graph is empty' {
        $BasePath = $script:fakeRoot
        $result = Test-ContentDependencies -ContentPath (Join-Path $script:fakeRoot 'AnalyticalRules/Anything.yaml')
        $result.Passed  | Should -BeTrue
        @($result.Missing).Count | Should -Be 0
    }

    It 'returns Passed=true when the path is not in the graph (no declared prereqs)' {
        $BasePath = $script:fakeRoot
        $script:DependencyGraph['AnalyticalRules/Other.yaml'] = @{ tables = @('T') }

        $result = Test-ContentDependencies -ContentPath (Join-Path $script:fakeRoot 'AnalyticalRules/Mine.yaml')
        $result.Passed  | Should -BeTrue
        @($result.Missing).Count | Should -Be 0
    }

    It 'reports table:X as missing when the workspace lacks the named table' {
        $BasePath = $script:fakeRoot
        $script:DependencyGraph['AnalyticalRules/X.yaml'] = @{ tables = @('AbsentTable') }
        $script:WorkspaceTables = @('PresentTable')   # lookup non-empty so the check fires

        $result = Test-ContentDependencies -ContentPath (Join-Path $script:fakeRoot 'AnalyticalRules/X.yaml')
        $result.Passed  | Should -BeFalse
        @($result.Missing) | Should -Contain 'table:AbsentTable'
    }

    It 'considers a watchlist satisfied when present in the workspace' {
        $BasePath = $script:fakeRoot
        $script:DependencyGraph['AnalyticalRules/X.yaml'] = @{ watchlists = @('Foo') }
        $script:WorkspaceWatchlists = @('Foo')

        $result = Test-ContentDependencies -ContentPath (Join-Path $script:fakeRoot 'AnalyticalRules/X.yaml')
        $result.Passed | Should -BeTrue
    }

    It 'considers a watchlist satisfied when present in the in-repo internal watchlists' {
        $BasePath = $script:fakeRoot
        $script:DependencyGraph['AnalyticalRules/X.yaml'] = @{ watchlists = @('Bar') }
        $script:InternalWatchlists = @('Bar')

        $result = Test-ContentDependencies -ContentPath (Join-Path $script:fakeRoot 'AnalyticalRules/X.yaml')
        $result.Passed | Should -BeTrue
    }

    It 'considers a function satisfied when present in workspace OR repo parsers' {
        $BasePath = $script:fakeRoot
        $script:DependencyGraph['AnalyticalRules/X.yaml'] = @{ functions = @('UnifiedSignInLogs') }

        # Test 1: workspace-only
        $script:WorkspaceFunctions = @('UnifiedSignInLogs')
        $script:InternalParsers    = @()
        (Test-ContentDependencies -ContentPath (Join-Path $script:fakeRoot 'AnalyticalRules/X.yaml')).Passed | Should -BeTrue

        # Test 2: repo-only
        $script:WorkspaceFunctions = @()
        $script:InternalParsers    = @('UnifiedSignInLogs')
        (Test-ContentDependencies -ContentPath (Join-Path $script:fakeRoot 'AnalyticalRules/X.yaml')).Passed | Should -BeTrue

        # Test 3: neither
        $script:WorkspaceFunctions = @()
        $script:InternalParsers    = @()
        $result = Test-ContentDependencies -ContentPath (Join-Path $script:fakeRoot 'AnalyticalRules/X.yaml')
        $result.Passed | Should -BeFalse
        @($result.Missing) | Should -Contain 'function:UnifiedSignInLogs'
    }

    It 'reports every missing prerequisite when multiple are absent' {
        $BasePath = $script:fakeRoot
        $script:DependencyGraph['AnalyticalRules/X.yaml'] = @{
            tables     = @('TableA', 'TableB')
            watchlists = @('WatchlistA')
            functions  = @('FunctionA')
        }
        $script:WorkspaceTables = @('TableA')   # TableB missing; WatchlistA / FunctionA missing too

        $result = Test-ContentDependencies -ContentPath (Join-Path $script:fakeRoot 'AnalyticalRules/X.yaml')
        $result.Passed | Should -BeFalse
        @($result.Missing) | Should -Contain 'table:TableB'
        @($result.Missing) | Should -Contain 'watchlist:WatchlistA'
        @($result.Missing) | Should -Contain 'function:FunctionA'
        @($result.Missing) | Should -Not -Contain 'table:TableA'
    }
}

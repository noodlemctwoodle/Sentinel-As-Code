#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester 5 tests for the pure functions in Scripts/Test-SentinelRuleDrift.ps1.

.DESCRIPTION
    Covers the four functions that own the substantive comparison and
    YAML-rewrite logic:

      - Compare-SentinelRule
      - Update-RuleYamlFile
      - Get-LineDiff
      - Resolve-RuleSource

    Plus the small helpers they depend on (Convert-TriggerOperator,
    ConvertTo-ShortTriggerOperator, ConvertTo-NormalisedYamlRule,
    Test-IsMultiLine).

    The test harness extracts every top-level function from the source script
    via the PowerShell AST and dot-sources just those into the test scope.
    This lets us exercise pure functions without triggering the script's
    Invoke-Main entry-point (which would try to authenticate to Azure).

.NOTES
    Run all tests:
        Invoke-Pester -Path Tests/Test-SentinelRuleDrift.Tests.ps1

    Run a single Describe block:
        Invoke-Pester -Path Tests/Test-SentinelRuleDrift.Tests.ps1 -FullName '*Compare-SentinelRule*'

    Verbose output:
        Invoke-Pester -Path Tests/Test-SentinelRuleDrift.Tests.ps1 -Output Detailed

    Prerequisites:
        - Pester 5+ (Install-Module Pester -Force -SkipPublisherCheck)
        - powershell-yaml (auto-installed by the YAML-related tests if missing)
#>

BeforeAll {
    $repoRoot   = Split-Path -Parent $PSScriptRoot
    $scriptPath = Join-Path -Path $repoRoot -ChildPath 'Scripts/Test-SentinelRuleDrift.ps1'

    # Extract every top-level function via the AST and dot-source just those.
    # Avoids running the param block, the #Requires directive, and Invoke-Main.
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $scriptPath, [ref]$tokens, [ref]$errors
    )
    if ($errors -and $errors.Count -gt 0) {
        throw "Parser errors in $scriptPath : $($errors -join '; ')"
    }
    $funcs = $ast.FindAll(
        { param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] },
        $false
    )
    $src = ($funcs | ForEach-Object { $_.Extent.Text }) -join "`n`n"

    # Script-scoped constants the extracted functions reference
    $script:DiffSnippetLength  = 0
    $script:SentinelApiVersion = '2025-09-01'
    $script:ManagedRuleKinds   = @(
        'Fusion'
        'MicrosoftSecurityIncidentCreation'
        'MLBehaviorAnalytics'
        'ThreatIntelligence'
    )

    . ([ScriptBlock]::Create($src))

    if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
        Install-Module -Name powershell-yaml -Force -Scope CurrentUser -AllowClobber | Out-Null
    }
    Import-Module powershell-yaml -ErrorAction Stop

    # Reusable mock builders. Defined here so every Describe can build
    # variations without rewriting the same property bag.
    function New-DeployedScheduled {
        param([hashtable]$Override = @{})
        $base = @{
            kind             = 'Scheduled'
            displayName      = 'Mock rule'
            severity         = 'Medium'
            query            = 'T | take 1'
            enabled          = $true
            queryFrequency   = 'PT5M'
            queryPeriod      = 'PT5M'
            triggerOperator  = 'GreaterThan'
            triggerThreshold = 0
        }
        foreach ($k in $Override.Keys) { $base[$k] = $Override[$k] }
        return $base
    }

    function New-DeployedNrt {
        param([hashtable]$Override = @{})
        $base = @{
            kind        = 'NRT'
            displayName = 'Mock NRT rule'
            severity    = 'Low'
            query       = 'T'
            enabled     = $true
        }
        foreach ($k in $Override.Keys) { $base[$k] = $Override[$k] }
        return $base
    }

    function Get-FixtureYamlPath {
        Join-Path $repoRoot 'AnalyticalRules/AzureActivity/AzureVmRunCommandExecutionDetectionRule.yaml'
    }
}

# ---------------------------------------------------------------------------
Describe 'Compare-SentinelRule' {
    Context 'Identical rules' {
        It 'reports no drift when deployed equals expected' {
            $rule = New-DeployedScheduled
            $diff = Compare-SentinelRule -Deployed $rule -Expected $rule
            $diff.HasDrift | Should -BeFalse
            $diff.Modifications.Count | Should -Be 0
        }
    }

    Context 'Single-field drift' {
        It 'detects severity change' {
            $deployed = New-DeployedScheduled @{ severity = 'High' }
            $expected = New-DeployedScheduled
            $diff = Compare-SentinelRule -Deployed $deployed -Expected $expected
            $diff.HasDrift | Should -BeTrue
            $diff.Modifications[0].Field | Should -Be 'severity'
            $diff.Modifications[0].Deployed | Should -Be 'High'
            $diff.Modifications[0].Expected | Should -Be 'Medium'
        }

        It 'detects query change' {
            $deployed = New-DeployedScheduled @{ query = 'T | take 99' }
            $expected = New-DeployedScheduled
            $diff = Compare-SentinelRule -Deployed $deployed -Expected $expected
            $diff.HasDrift | Should -BeTrue
            $diff.Modifications.Field | Should -Be 'query'
        }

        It 'detects triggerThreshold change' {
            $deployed = New-DeployedScheduled @{ triggerThreshold = 5 }
            $expected = New-DeployedScheduled
            $diff = Compare-SentinelRule -Deployed $deployed -Expected $expected
            $diff.HasDrift | Should -BeTrue
            $diff.Modifications.Field | Should -Be 'triggerThreshold'
        }

        It 'detects displayName change' {
            $deployed = New-DeployedScheduled @{ displayName = 'Renamed in portal' }
            $expected = New-DeployedScheduled
            $diff = Compare-SentinelRule -Deployed $deployed -Expected $expected
            $diff.HasDrift | Should -BeTrue
            $diff.Modifications.Field | Should -Be 'displayName'
        }
    }

    Context 'Multi-field drift' {
        It 'reports every modified field' {
            $deployed = New-DeployedScheduled @{ severity = 'High'; query = 'T | take 99'; triggerThreshold = 5 }
            $expected = New-DeployedScheduled
            $diff = Compare-SentinelRule -Deployed $deployed -Expected $expected
            $diff.HasDrift | Should -BeTrue
            $diff.Modifications.Count | Should -Be 3
            ($diff.Modifications | ForEach-Object { $_.Field } | Sort-Object) -join ',' |
                Should -Be 'query,severity,triggerThreshold'
        }
    }

    Context 'Excluded fields' {
        It 'does not flag enabled mismatch as drift' {
            $deployed = New-DeployedScheduled @{ enabled = $false }
            $expected = New-DeployedScheduled
            $diff = Compare-SentinelRule -Deployed $deployed -Expected $expected
            $diff.HasDrift | Should -BeFalse
        }

        It 'reports query drift even when enabled also differs' {
            $deployed = New-DeployedScheduled @{ enabled = $false; query = 'T | take 99' }
            $expected = New-DeployedScheduled
            $diff = Compare-SentinelRule -Deployed $deployed -Expected $expected
            $diff.HasDrift | Should -BeTrue
            $diff.Modifications.Count | Should -Be 1
            $diff.Modifications[0].Field | Should -Be 'query'
        }
    }

    Context 'Case sensitivity' {
        It 'treats severity comparison case-insensitively' {
            $deployed = New-DeployedScheduled @{ severity = 'medium' }
            $expected = New-DeployedScheduled @{ severity = 'Medium' }
            (Compare-SentinelRule -Deployed $deployed -Expected $expected).HasDrift |
                Should -BeFalse
        }

        It 'treats triggerOperator comparison case-insensitively' {
            $deployed = New-DeployedScheduled @{ triggerOperator = 'GREATERTHAN' }
            $expected = New-DeployedScheduled @{ triggerOperator = 'GreaterThan' }
            (Compare-SentinelRule -Deployed $deployed -Expected $expected).HasDrift |
                Should -BeFalse
        }
    }

    Context 'NRT rules' {
        It 'compares query, severity, and displayName for NRT' {
            $deployed = New-DeployedNrt @{ severity = 'High' }
            $expected = New-DeployedNrt
            $diff = Compare-SentinelRule -Deployed $deployed -Expected $expected
            $diff.HasDrift | Should -BeTrue
            $diff.Modifications.Field | Should -Be 'severity'
        }

        It 'does not compare scheduling fields for NRT' {
            # If we provide scheduling fields on an NRT rule, they should be ignored.
            $deployed = New-DeployedNrt @{ queryFrequency = 'PT5M' }
            $expected = New-DeployedNrt @{ queryFrequency = 'PT1H' }
            $diff = Compare-SentinelRule -Deployed $deployed -Expected $expected
            $diff.HasDrift | Should -BeFalse
        }
    }

    Context 'Null/missing values' {
        It 'skips a field when expected is null' {
            $deployed = New-DeployedScheduled @{ severity = 'High' }
            $expected = New-DeployedScheduled
            $expected.severity = $null
            (Compare-SentinelRule -Deployed $deployed -Expected $expected).HasDrift |
                Should -BeFalse
        }
    }

    Context 'Diff payload shape' {
        It 'returns Modifications with Field/Deployed/Expected keys' {
            $deployed = New-DeployedScheduled @{ severity = 'High' }
            $expected = New-DeployedScheduled
            $mod = (Compare-SentinelRule -Deployed $deployed -Expected $expected).Modifications[0]
            $mod.Keys | Should -Contain 'Field'
            $mod.Keys | Should -Contain 'Deployed'
            $mod.Keys | Should -Contain 'Expected'
        }
    }
}

# ---------------------------------------------------------------------------
Describe 'Update-RuleYamlFile' {
    BeforeAll {
        $script:fixturePath = Get-FixtureYamlPath
        if (-not (Test-Path $script:fixturePath)) {
            throw "Required fixture not found: $script:fixturePath"
        }
    }

    Context 'Single-line scalar edits' {
        BeforeEach {
            $script:tmp = Join-Path $TestDrive "rule-$([Guid]::NewGuid()).yaml"
            Copy-Item -Path $fixturePath -Destination $script:tmp
        }

        It 'rewrites severity in place' {
            $mods = @(@{ Field = 'severity'; Deployed = 'High'; Expected = 'Medium' })
            Update-RuleYamlFile -FilePath $tmp -Modifications $mods | Should -BeTrue
            Get-Content -Raw $tmp | Should -Match '(?m)^severity:\s+High\s*$'
        }

        It 'rewrites triggerThreshold' {
            $mods = @(@{ Field = 'triggerThreshold'; Deployed = 5; Expected = 0 })
            Update-RuleYamlFile -FilePath $tmp -Modifications $mods | Should -BeTrue
            Get-Content -Raw $tmp | Should -Match '(?m)^triggerThreshold:\s+5\s*$'
        }

        It 'rewrites triggerOperator using the YAML short form' {
            $mods = @(@{ Field = 'triggerOperator'; Deployed = 'LessThan'; Expected = 'GreaterThan' })
            Update-RuleYamlFile -FilePath $tmp -Modifications $mods | Should -BeTrue
            Get-Content -Raw $tmp | Should -Match '(?m)^triggerOperator:\s+lt\s*$'
        }

        It 'rewrites queryFrequency' {
            $mods = @(@{ Field = 'queryFrequency'; Deployed = 'PT1H'; Expected = 'PT30M' })
            Update-RuleYamlFile -FilePath $tmp -Modifications $mods | Should -BeTrue
            Get-Content -Raw $tmp | Should -Match '(?m)^queryFrequency:\s+PT1H\s*$'
        }

        It 'rewrites queryPeriod' {
            $mods = @(@{ Field = 'queryPeriod'; Deployed = 'PT2H'; Expected = 'PT35M' })
            Update-RuleYamlFile -FilePath $tmp -Modifications $mods | Should -BeTrue
            Get-Content -Raw $tmp | Should -Match '(?m)^queryPeriod:\s+PT2H\s*$'
        }

        It 'rewrites displayName via the YAML name field' {
            $mods = @(@{ Field = 'displayName'; Deployed = 'Renamed in portal'; Expected = 'Old name' })
            Update-RuleYamlFile -FilePath $tmp -Modifications $mods | Should -BeTrue
            Get-Content -Raw $tmp | Should -Match '(?m)^name:\s+Renamed in portal\s*$'
        }
    }

    Context 'Query block edits' {
        BeforeEach {
            $script:tmp = Join-Path $TestDrive "rule-$([Guid]::NewGuid()).yaml"
            Copy-Item -Path $fixturePath -Destination $script:tmp
        }

        It 'replaces the query block scalar without consuming subsequent fields' {
            $newQuery = "AzureActivity`n| take 100"
            $mods = @(@{ Field = 'query'; Deployed = $newQuery; Expected = 'old' })
            Update-RuleYamlFile -FilePath $tmp -Modifications $mods | Should -BeTrue

            $updated = Get-Content -Raw $tmp
            $updated | Should -Match 'take 100'
            $updated | Should -Not -Match 'Microsoft\.Compute/virtualMachines/runCommand'

            # Crucially: every section that lives AFTER the query block in the fixture
            # must still be intact (the regex must not have eaten them).
            $updated | Should -Match '(?m)^entityMappings:'
            $updated | Should -Match '(?m)^eventGroupingSettings:'
            $updated | Should -Match '(?m)^incidentConfiguration:'
            $updated | Should -Match '(?m)^version:'
            $updated | Should -Match '(?m)^kind:\s+Scheduled'
            $updated | Should -Match '(?m)^tags:'
        }
    }

    Context 'Preservation of unrelated fields' {
        It 'leaves description, requiredDataConnectors, entityMappings, tags untouched' {
            $tmp = Join-Path $TestDrive "rule-$([Guid]::NewGuid()).yaml"
            Copy-Item -Path $fixturePath -Destination $tmp

            $mods = @(@{ Field = 'severity'; Deployed = 'High'; Expected = 'Medium' })
            Update-RuleYamlFile -FilePath $tmp -Modifications $mods | Should -BeTrue

            $updated = Get-Content -Raw $tmp
            $updated | Should -Match '(?ms)^description:\s+\|'
            $updated | Should -Match '(?m)^requiredDataConnectors:'
            $updated | Should -Match '(?m)^entityMappings:'
            $updated | Should -Match '(?m)^tags:'
            $updated | Should -Match '(?m)^id:\s+303e7728'
        }
    }

    Context 'Version bump' {
        It 'bumps the patch component when a change is applied' {
            $tmp = Join-Path $TestDrive "rule-$([Guid]::NewGuid()).yaml"
            Copy-Item -Path $fixturePath -Destination $tmp

            (Get-Content -Raw $tmp) | Should -Match '(?m)^version:\s+1\.0\.0\b'

            $mods = @(@{ Field = 'severity'; Deployed = 'High'; Expected = 'Medium' })
            Update-RuleYamlFile -FilePath $tmp -Modifications $mods | Should -BeTrue

            Get-Content -Raw $tmp | Should -Match '(?m)^version:\s+1\.0\.1\b'
        }
    }

    Context 'Return value' {
        It 'returns true when content actually changed' {
            $tmp = Join-Path $TestDrive "rule-$([Guid]::NewGuid()).yaml"
            Copy-Item -Path $fixturePath -Destination $tmp

            $mods = @(@{ Field = 'severity'; Deployed = 'High'; Expected = 'Medium' })
            Update-RuleYamlFile -FilePath $tmp -Modifications $mods | Should -BeTrue
        }

        It 'returns false when no recognised field was modified' {
            $tmp = Join-Path $TestDrive "rule-$([Guid]::NewGuid()).yaml"
            Copy-Item -Path $fixturePath -Destination $tmp

            # Field that the function doesn't know how to write — should no-op
            $mods = @(@{ Field = 'tactics'; Deployed = 'Execution'; Expected = 'PrivilegeEscalation' })
            Update-RuleYamlFile -FilePath $tmp -Modifications $mods | Should -BeFalse
        }
    }
}

# ---------------------------------------------------------------------------
Describe 'Get-LineDiff' {
    Context 'Identical inputs' {
        It 'emits only context lines for identical input' {
            $diff = Get-LineDiff -Before "alpha`nbeta`ngamma" -After "alpha`nbeta`ngamma"
            $diff -split "`n" | ForEach-Object { $_ | Should -Match '^  ' }
        }
    }

    Context 'Pure insertions' {
        It 'emits + lines for added content' {
            $diff = Get-LineDiff -Before "alpha`ngamma" -After "alpha`nbeta`ngamma"
            ($diff -split "`n") | Should -Contain '+ beta'
        }
    }

    Context 'Pure deletions' {
        It 'emits - lines for removed content' {
            $diff = Get-LineDiff -Before "alpha`nbeta`ngamma" -After "alpha`ngamma"
            ($diff -split "`n") | Should -Contain '- beta'
        }
    }

    Context 'Modifications' {
        It 'reports the changed line as a delete + add pair' {
            $diff = Get-LineDiff -Before "alpha`nbeta`ngamma" -After "alpha`nBETA`ngamma"
            ($diff -split "`n") | Should -Contain '- beta'
            ($diff -split "`n") | Should -Contain '+ BETA'
        }

        It 'preserves the order of unchanged surrounding lines' {
            $diff = Get-LineDiff -Before "alpha`nbeta`ngamma" -After "alpha`nBETA`ngamma"
            $lines = $diff -split "`n"
            $lines[0] | Should -Be '  alpha'
            $lines[-1] | Should -Be '  gamma'
        }
    }

    Context 'Empty inputs' {
        It 'handles empty before' {
            $diff = Get-LineDiff -Before '' -After "alpha`nbeta"
            ($diff -split "`n") | Should -Contain '+ alpha'
            ($diff -split "`n") | Should -Contain '+ beta'
        }

        It 'handles empty after' {
            $diff = Get-LineDiff -Before "alpha`nbeta" -After ''
            ($diff -split "`n") | Should -Contain '- alpha'
            ($diff -split "`n") | Should -Contain '- beta'
        }
    }

    Context 'Case sensitivity' {
        It 'treats lines as different when only case differs' {
            $diff = Get-LineDiff -Before 'alpha' -After 'ALPHA'
            ($diff -split "`n") | Should -Contain '- alpha'
            ($diff -split "`n") | Should -Contain '+ ALPHA'
        }
    }
}

# ---------------------------------------------------------------------------
Describe 'Resolve-RuleSource' {
    BeforeAll {
        function New-DeployedRuleObject {
            param(
                [string]$Guid           = (New-Guid).Guid
                ,
                [string]$TemplateName   = $null
                ,
                [string]$DisplayName    = 'Mock rule'
            )
            [pscustomobject]@{
                name       = $Guid
                id         = "/subscriptions/x/resourceGroups/y/providers/Microsoft.SecurityInsights/alertRules/$Guid"
                kind       = 'Scheduled'
                properties = [pscustomobject]@{
                    alertRuleTemplateName = $TemplateName
                    displayName           = $DisplayName
                    severity              = 'Medium'
                    query                 = 'T | take 1'
                    enabled               = $true
                    queryFrequency        = 'PT5M'
                    queryPeriod           = 'PT5M'
                    triggerOperator       = 'GreaterThan'
                    triggerThreshold      = 0
                }
            }
        }

        # Fake Content Hub template object — minimum shape for ConvertTo-NormalisedTemplateRule
        $script:templateContentId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
        $script:fakeTemplate = [pscustomobject]@{
            name       = 'tmpl-1'
            properties = [pscustomobject]@{
                contentId   = $script:templateContentId
                packageId   = 'pkg-defenderxdr'
                mainTemplate = [pscustomobject]@{
                    resources = @(
                        [pscustomobject]@{
                            type       = 'Microsoft.OperationalInsights/workspaces/providers/alertRules'
                            kind       = 'Scheduled'
                            properties = [pscustomobject]@{
                                displayName      = 'Mock rule'
                                severity         = 'Medium'
                                query            = 'T | take 1'
                                queryFrequency   = 'PT5M'
                                queryPeriod      = 'PT5M'
                                triggerOperator  = 'GreaterThan'
                                triggerThreshold = 0
                            }
                        }
                    )
                }
            }
        }

        $script:templatesByContentId = @{ $script:templateContentId = $script:fakeTemplate }
        $script:solutionByPackageId  = @{ 'pkg-defenderxdr' = 'Microsoft Defender XDR' }
    }

    Context 'ContentHub branch' {
        It 'resolves to ContentHub when alertRuleTemplateName matches' {
            $rule = New-DeployedRuleObject -TemplateName $templateContentId
            $resolved = Resolve-RuleSource `
                -Rule $rule `
                -TemplatesByContentId $templatesByContentId `
                -YamlsByGuid @{} `
                -SolutionByPackageId $solutionByPackageId

            $resolved.Source    | Should -Be 'ContentHub'
            $resolved.SourceRef | Should -Be $templateContentId
            $resolved.Solution  | Should -Be 'Microsoft Defender XDR'
            $resolved.Expected  | Should -Not -BeNullOrEmpty
        }

        It 'returns no solution name when packageId is unknown' {
            $rule = New-DeployedRuleObject -TemplateName $templateContentId
            $resolved = Resolve-RuleSource `
                -Rule $rule `
                -TemplatesByContentId $templatesByContentId `
                -YamlsByGuid @{} `
                -SolutionByPackageId @{}

            $resolved.Source   | Should -Be 'ContentHub'
            $resolved.Solution | Should -BeNullOrEmpty
        }
    }

    Context 'Custom branch' {
        It 'resolves to Custom when GUID matches a YAML id' {
            $guid = (New-Guid).Guid
            $yamlEntry = @{
                FilePath    = '/repo/AnalyticalRules/Custom/foo.yaml'
                IsCommunity = $false
                Yaml        = @{
                    id               = $guid
                    name             = 'Mock rule'
                    severity         = 'Medium'
                    query            = 'T | take 1'
                    queryFrequency   = 'PT5M'
                    queryPeriod      = 'PT5M'
                    triggerOperator  = 'gt'
                    triggerThreshold = 0
                    kind             = 'Scheduled'
                }
            }
            $yamlMap = @{ $guid.ToLowerInvariant() = $yamlEntry }

            $rule = New-DeployedRuleObject -Guid $guid -TemplateName ''
            $resolved = Resolve-RuleSource `
                -Rule $rule `
                -TemplatesByContentId @{} `
                -YamlsByGuid $yamlMap `
                -SolutionByPackageId @{}

            $resolved.Source    | Should -Be 'Custom'
            $resolved.SourceRef | Should -Be '/repo/AnalyticalRules/Custom/foo.yaml'
            $resolved.Expected  | Should -Not -BeNullOrEmpty
            # The Custom branch normalises YAML triggerOperator to API form
            $resolved.Expected.triggerOperator | Should -Be 'GreaterThan'
        }

        It 'matches GUIDs case-insensitively' {
            $guid = '11111111-2222-3333-4444-555555555555'
            $yamlEntry = @{
                FilePath = '/repo/x.yaml'; IsCommunity = $false
                Yaml = @{ id = $guid; name = 'r'; severity = 'Low'; query = 'T'; kind = 'NRT' }
            }
            $yamlMap = @{ $guid = $yamlEntry }

            # Deployed rule resource-name uppercase
            $rule = New-DeployedRuleObject -Guid $guid.ToUpperInvariant() -TemplateName ''
            $resolved = Resolve-RuleSource `
                -Rule $rule -TemplatesByContentId @{} -YamlsByGuid $yamlMap -SolutionByPackageId @{}
            $resolved.Source | Should -Be 'Custom'
        }
    }

    Context 'Orphan branch' {
        It 'resolves to Orphan when neither matches' {
            $rule = New-DeployedRuleObject -TemplateName $null
            $resolved = Resolve-RuleSource `
                -Rule $rule -TemplatesByContentId @{} -YamlsByGuid @{} -SolutionByPackageId @{}
            $resolved.Source   | Should -Be 'Orphan'
            $resolved.Expected | Should -BeNullOrEmpty
        }

        It 'treats empty alertRuleTemplateName as null' {
            $rule = New-DeployedRuleObject -TemplateName ''
            $resolved = Resolve-RuleSource `
                -Rule $rule -TemplatesByContentId @{} -YamlsByGuid @{} -SolutionByPackageId @{}
            $resolved.Source | Should -Be 'Orphan'
        }

        It 'is Orphan when alertRuleTemplateName is set but unknown to the lookup' {
            $rule = New-DeployedRuleObject -TemplateName 'unknown-template-id'
            $resolved = Resolve-RuleSource `
                -Rule $rule -TemplatesByContentId $templatesByContentId -YamlsByGuid @{} -SolutionByPackageId @{}
            $resolved.Source | Should -Be 'Orphan'
        }
    }

    Context 'Branch precedence' {
        It 'prefers ContentHub over Custom when both could match' {
            $guid = (New-Guid).Guid
            $yamlEntry = @{
                FilePath = '/repo/x.yaml'; IsCommunity = $false
                Yaml = @{ id = $guid; name = 'r'; severity = 'Low'; query = 'T'; kind = 'NRT' }
            }
            $yamlMap = @{ $guid.ToLowerInvariant() = $yamlEntry }

            # Rule has both a template link AND its GUID is in the YAML map.
            # Resolution must prefer ContentHub (template link is stronger evidence
            # of provenance than a GUID coincidence).
            $rule = New-DeployedRuleObject -Guid $guid -TemplateName $templateContentId
            $resolved = Resolve-RuleSource `
                -Rule $rule `
                -TemplatesByContentId $templatesByContentId `
                -YamlsByGuid $yamlMap `
                -SolutionByPackageId $solutionByPackageId

            $resolved.Source | Should -Be 'ContentHub'
        }
    }
}

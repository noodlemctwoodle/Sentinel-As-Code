#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester 5 schema validation for every playbook under Content/Playbooks/:
    each Bicep file and each ARM JSON template.

.DESCRIPTION
    Generates one It block per playbook file via -ForEach so per-file
    pass/fail surfaces directly in the PR check UI.

    The Bicep files are compiled together, once, through the
    iSOCDeployments module's Invoke-iSOCBicep (the Bicep CLI must be on the
    PATH), and each must build with no error and no warning:
    Content/Playbooks/bicepconfig.json and the module's writer keep a
    playbook warning-free, so a warning means something new is wrong. A
    JSON file is parsed as it is. Either way the ARM template is held to
    the structural invariants every Sentinel playbook must satisfy to
    deploy through Deploy-iSOCContent:

    - Parses as JSON, or compiles, with a mapping at the root.
    - `$schema` is the ARM deploymentTemplate URL.
    - `contentVersion` is present.
    - `resources` array contains at least one Microsoft.Logic/workflows
      resource.
    - The workflow has properties.definition.triggers (at least one) and
      properties.definition.actions (the workflow body).
    - `parameters` has at least one parameter (a Sentinel playbook needs
      either PlaybookName or LogicAppName so the deployer can name it).

    Cross-file uniqueness on PlaybookName is INTENTIONALLY NOT enforced:
    several playbooks ship in both Entity/ and Incident/ tiers with the
    same defaultValue (e.g. RevokeSessions, VirusTotalIPReport), and the
    deploy logic is expected to distinguish them via tier/parent.

.EXAMPLE
    Invoke-Pester -Path Tests/Test-PlaybookArm.Tests.ps1

    Validates every playbook in the repo.

.EXAMPLE
    Invoke-Pester -Path Tests/Test-PlaybookArm.Tests.ps1 -Output Detailed

    Runs with per-assertion output, for identifying which playbook is
    missing a trigger, action or parameter.

.NOTES
    File:         Tests/Test-PlaybookArm.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-05-13
    Version:      0.2.0
    Last Updated: 2026-11-06
    Requires:     PowerShell 7.2+, Pester 5+, the Bicep CLI
#>

BeforeDiscovery {
    $repoRoot = Split-Path -Parent $PSScriptRoot

    # Scaffold / starter playbooks that are deliberately incomplete (no
    # actions, no real trigger). The schema test still validates everything
    # else, but skips the "non-empty triggers/actions" check for these.
    # If you turn one of these into a real playbook, remove its entry here.
    # Set in BeforeDiscovery so test-case data carries the Skeleton flag —
    # -Skip: predicates evaluate at discovery and need static data.
    $skeletonPlaybooks = @(
        'Content/Playbooks/Template/Template.bicep',
        'Content/Playbooks/Other/Schedule-AutomationRules.bicep',
        'Content/Playbooks/Alert/AzureOpenAIAssistant.bicep'
    )

    $script:playbookCases = @()
    $playbookRoot = Join-Path $repoRoot 'Content/Playbooks'
    if (Test-Path $playbookRoot) {
        $files = @(Get-ChildItem -Path $playbookRoot -Recurse -File |
                Where-Object { $_.Extension -in '.bicep', '.json' -and $_.Name -ne 'bicepconfig.json' -and $_.Name -notlike '*.parameters.json' } |
                Sort-Object FullName)

        # Every Bicep file compiled in one run of the CLI, through the
        # module's own wrapper.
        $builds = @{}
        $bicepFiles = @($files | Where-Object Extension -eq '.bicep')
        if ($bicepFiles.Count -gt 0) {
            if (-not (Get-Command bicep -CommandType Application -ErrorAction SilentlyContinue)) {
                foreach ($file in $bicepFiles) { $builds[$file.FullName] = [pscustomobject]@{ Succeeded = $false; Json = $null; Errors = @('The Bicep CLI is not on the PATH: install it with az bicep install and put ~/.azure/bin on the PATH.'); Warnings = @() } }
            }
            else {
                $module = Import-Module (Join-Path $repoRoot 'Modules/iSOCDeployments/iSOCDeployments.psd1') -Force -PassThru
                foreach ($build in @(& $module { param($Paths) Invoke-iSOCBicep -Path $Paths } @($bicepFiles.FullName))) { $builds[$build.Path] = $build }
            }
        }

        $script:playbookCases = @($files | ForEach-Object {
            $rel = ($_.FullName.Substring($repoRoot.Length + 1)) -replace '\\', '/'
            $arm = $null
            $parseError = $null
            $warnings = @()
            try {
                if ($_.Extension -eq '.bicep') {
                    $build = $builds[[System.IO.Path]::GetFullPath($_.FullName)]
                    $warnings = @($build.Warnings)
                    if (-not $build.Succeeded) { throw "does not compile: $(@($build.Errors) -join ' ')" }
                    $raw = $build.Json
                }
                else {
                    $raw = Get-Content -Path $_.FullName -Raw -ErrorAction Stop
                }
                if ([string]::IsNullOrWhiteSpace($raw)) { throw 'File is empty' }
                $arm = ConvertFrom-Json -InputObject $raw -Depth 64 -AsHashtable -ErrorAction Stop
            }
            catch {
                $parseError = $_.Exception.Message
            }

            $tier = ''
            $relParts = $rel -split '/'
            if ($relParts.Count -ge 2) { $tier = $relParts[1] }

            @{
                Path         = $_.FullName
                RelativePath = $rel
                Arm          = $arm
                ParseError   = $parseError
                ParseFailed  = ($null -ne $parseError) -or ($null -eq $arm)
                Tier         = $tier
                IsSkeleton   = ($skeletonPlaybooks -contains $rel)
                IsBicep      = ($_.Extension -eq '.bicep')
                Warnings     = $warnings
            }
        })
    }
}

BeforeAll {
    $script:DeploymentTemplateSchema = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#'
    $script:WorkflowResourceType     = 'Microsoft.Logic/workflows'
    $script:NamingParameters         = @('PlaybookName', 'LogicAppName')
}

Describe 'Playbook: <RelativePath>' -ForEach $script:playbookCases {

    It 'parses as JSON, or compiles, with a mapping at the root' {
        $ParseError | Should -BeNullOrEmpty
        $Arm        | Should -Not -BeNullOrEmpty
        ($Arm -is [System.Collections.IDictionary]) | Should -BeTrue
    }

    It 'builds without warnings' -Skip:(-not $IsBicep) {
        @($Warnings) | Should -BeNullOrEmpty -Because 'Content/Playbooks/bicepconfig.json and the module''s writer keep a playbook warning-free'
    }

    Context 'ARM template top-level' -Skip:$ParseFailed {
        It 'has the deploymentTemplate $schema URL' {
            $Arm.ContainsKey('$schema') | Should -BeTrue
            [string]$Arm.'$schema' | Should -Be $script:DeploymentTemplateSchema
        }

        It 'has a contentVersion' {
            $Arm.ContainsKey('contentVersion') | Should -BeTrue
            ([string]$Arm.contentVersion).Trim() | Should -Not -BeNullOrEmpty
        }

        It 'has a non-empty resources array' {
            $Arm.ContainsKey('resources') | Should -BeTrue
            (@($Arm.resources).Count -gt 0) | Should -BeTrue
        }

        It 'has a non-empty parameters object' {
            $Arm.ContainsKey('parameters') | Should -BeTrue
            ($Arm.parameters -is [System.Collections.IDictionary]) | Should -BeTrue
            $Arm.parameters.Keys.Count | Should -BeGreaterThan 0 -Because 'every playbook needs at least one parameter for the deployer to inject (PlaybookName / LogicAppName)'
        }

        It 'declares a naming parameter (PlaybookName or LogicAppName)' {
            $found = $script:NamingParameters | Where-Object { $Arm.parameters.ContainsKey($_) }
            $found | Should -Not -BeNullOrEmpty -Because "playbook must declare one of: $($script:NamingParameters -join ', ') so the deployer can resolve the workflow resource name"
        }
    }

    Context 'Workflow resource' -Skip:($ParseFailed -or -not $Arm.ContainsKey('resources')) {
        It 'has at least one Microsoft.Logic/workflows resource' {
            $workflows = @($Arm.resources | Where-Object {
                $_ -is [System.Collections.IDictionary] -and
                [string]$_.type -eq $script:WorkflowResourceType
            })
            $workflows.Count | Should -BeGreaterOrEqual 1 -Because "playbook must contain at least one $script:WorkflowResourceType resource"
        }

        It 'workflow resource has a properties.definition' {
            $workflows = @($Arm.resources | Where-Object {
                $_ -is [System.Collections.IDictionary] -and
                [string]$_.type -eq $script:WorkflowResourceType
            })
            foreach ($wf in $workflows) {
                $wf.ContainsKey('properties') | Should -BeTrue
                ($wf.properties -is [System.Collections.IDictionary]) | Should -BeTrue
                $wf.properties.ContainsKey('definition') | Should -BeTrue
                ($wf.properties.definition -is [System.Collections.IDictionary]) | Should -BeTrue

                $def = $wf.properties.definition
                $def.ContainsKey('triggers') | Should -BeTrue
                ($def.triggers -is [System.Collections.IDictionary]) | Should -BeTrue
                $def.ContainsKey('actions') | Should -BeTrue
                ($def.actions -is [System.Collections.IDictionary]) | Should -BeTrue
            }
        }

        It 'workflow has at least one trigger and one action (skeleton playbooks excepted)' -Skip:$IsSkeleton {
            $workflows = @($Arm.resources | Where-Object {
                $_ -is [System.Collections.IDictionary] -and
                [string]$_.type -eq $script:WorkflowResourceType
            })
            foreach ($wf in $workflows) {
                $def = $wf.properties.definition
                $def.triggers.Keys.Count | Should -BeGreaterThan 0 -Because 'a playbook with no trigger never fires'
                $def.actions.Keys.Count  | Should -BeGreaterThan 0 -Because 'a playbook with no actions has no body'
            }
        }
    }

    Context 'Optional metadata block' -Skip:$ParseFailed {
        It 'metadata is an object when present' {
            if ($Arm.ContainsKey('metadata')) {
                ($Arm.metadata -is [System.Collections.IDictionary]) | Should -BeTrue
            }
        }
    }
}

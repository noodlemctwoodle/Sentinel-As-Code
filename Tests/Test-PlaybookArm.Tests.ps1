#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester 5 schema validation for every Playbooks/**/*.json (ARM templates).

.DESCRIPTION
    Generates one It block per playbook file via -ForEach so per-file
    pass/fail surfaces directly in the PR check UI.

    Validates the structural invariants every Sentinel playbook must satisfy
    to deploy through Deploy-CustomContent.ps1:

    - Parses as JSON with a mapping at the root.
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

.NOTES
    Run all tests:
        Invoke-Pester -Path Tests/Test-PlaybookArm.Tests.ps1
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
        'Playbooks/Template/Template.json',
        'Playbooks/Other/Schedule-AutomationRules.json',
        'Playbooks/Alert/AzureOpenAIAssistant.json'
    )

    $script:playbookCases = @()
    $playbookRoot = Join-Path $repoRoot 'Playbooks'
    if (Test-Path $playbookRoot) {
        $script:playbookCases = @(Get-ChildItem -Path $playbookRoot -Recurse -Filter '*.json' -File | ForEach-Object {
            $rel = ($_.FullName.Substring($repoRoot.Length + 1)) -replace '\\', '/'
            $arm = $null
            $parseError = $null
            try {
                $raw = Get-Content -Path $_.FullName -Raw -ErrorAction Stop
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
            }
        })
    }
}

BeforeAll {
    $script:DeploymentTemplateSchema = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#'
    $script:WorkflowResourceType     = 'Microsoft.Logic/workflows'
    $script:NamingParameters         = @('PlaybookName', 'LogicAppName')
}

Describe 'Playbook ARM: <RelativePath>' -ForEach $script:playbookCases {

    It 'parses as JSON with a mapping at the root' {
        $ParseError | Should -BeNullOrEmpty
        $Arm        | Should -Not -BeNullOrEmpty
        ($Arm -is [System.Collections.IDictionary]) | Should -BeTrue
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

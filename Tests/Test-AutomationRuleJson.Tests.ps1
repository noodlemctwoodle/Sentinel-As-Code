#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester 5 schema validation for every JSON in AutomationRules/.

.DESCRIPTION
    Generates one It block per JSON file via -ForEach so per-file pass/fail
    surfaces directly in the PR check UI.

    Schema follows Docs/Content/Automation-Rules.md and the Sentinel
    automation-rule REST contract.

    Cross-file invariant: every rule's `automationRuleId` GUID must be
    unique across the tree (Sentinel uses it as the resource name).

.NOTES
    Run all tests:
        Invoke-Pester -Path Tests/Test-AutomationRuleJson.Tests.ps1
#>

BeforeDiscovery {
    $repoRoot = Split-Path -Parent $PSScriptRoot

    $script:automationRuleCases = @()
    $rulesRoot = Join-Path $repoRoot 'AutomationRules'
    if (Test-Path $rulesRoot) {
        $script:automationRuleCases = @(Get-ChildItem -Path $rulesRoot -Recurse -Filter '*.json' -File | ForEach-Object {
            $rel = ($_.FullName.Substring($repoRoot.Length + 1)) -replace '\\', '/'
            $json = $null
            $parseError = $null
            try {
                $raw = Get-Content -Path $_.FullName -Raw -ErrorAction Stop
                if ([string]::IsNullOrWhiteSpace($raw)) { throw 'File is empty' }
                $json = ConvertFrom-Json -InputObject $raw -Depth 32 -AsHashtable -ErrorAction Stop
            }
            catch {
                $parseError = $_.Exception.Message
            }

            @{
                Path         = $_.FullName
                RelativePath = $rel
                Json         = $json
                ParseError   = $parseError
                ParseFailed  = ($null -ne $parseError) -or ($null -eq $json)
            }
        })
    }
}

BeforeAll {
    $script:GuidPattern = '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'

    # Per Docs/Content/Automation-Rules.md.
    $script:ValidTriggersOn   = @('Incidents', 'Alerts')
    $script:ValidTriggersWhen = @('Created', 'Updated')
    $script:ValidConditionTypes = @('Property', 'PropertyArrayChanged', 'PropertyChanged')
    $script:ValidActionTypes = @('ModifyProperties', 'RunPlaybook', 'AddIncidentTask')

    $script:ValidPropertyOperators = @(
        'Equals', 'NotEquals',
        'Contains', 'NotContains',
        'StartsWith', 'NotStartsWith',
        'EndsWith', 'NotEndsWith'
    )

    $script:ValidArrayTypes  = @('Labels', 'Tactics', 'Alerts', 'Comments')
    $script:ValidArrayChange = @('Added', 'Removed')

    $script:ValidPropertyChangeTypes = @('ChangedFrom', 'ChangedTo')

    # Per Docs/Content/Automation-Rules.md "Action Types" section.
    $script:AddIncidentTaskTitleMaxLen = 150
}

Describe 'Automation rule schema: <RelativePath>' -ForEach $script:automationRuleCases {

    It 'parses as JSON with a mapping at the root' {
        $ParseError | Should -BeNullOrEmpty
        $Json       | Should -Not -BeNullOrEmpty
        ($Json -is [System.Collections.IDictionary]) | Should -BeTrue
    }

    Context 'Required top-level fields' -Skip:$ParseFailed {
        It 'has a GUID-format automationRuleId' {
            $Json.ContainsKey('automationRuleId') | Should -BeTrue
            [string]$Json.automationRuleId | Should -Match $script:GuidPattern -Because 'automationRuleId is the resource name in the PUT URL; must be a stable GUID'
        }

        It 'has a non-empty displayName' {
            $Json.ContainsKey('displayName') | Should -BeTrue
            ([string]$Json.displayName).Trim() | Should -Not -BeNullOrEmpty
        }

        It 'has an order in the 1-1000 range' {
            $Json.ContainsKey('order') | Should -BeTrue
            $orderValue = $Json.order
            ($orderValue -is [int] -or $orderValue -is [long]) | Should -BeTrue -Because 'order must be an integer'
            [int]$orderValue | Should -BeGreaterOrEqual 1
            [int]$orderValue | Should -BeLessOrEqual 1000
        }

        It 'has a triggeringLogic object' {
            $Json.ContainsKey('triggeringLogic') | Should -BeTrue
            ($Json.triggeringLogic -is [System.Collections.IDictionary]) | Should -BeTrue
        }

        It 'has a non-empty actions array' {
            $Json.ContainsKey('actions') | Should -BeTrue
            ($Json.actions -is [System.Collections.IEnumerable] -and -not ($Json.actions -is [string]) -and -not ($Json.actions -is [System.Collections.IDictionary])) | Should -BeTrue
            (@($Json.actions).Count -gt 0) | Should -BeTrue -Because 'an automation rule with zero actions has no effect on deploy'
        }
    }

    Context 'triggeringLogic shape' -Skip:($ParseFailed -or -not ($Json.triggeringLogic -is [System.Collections.IDictionary])) {
        It 'has isEnabled (boolean)' {
            $Json.triggeringLogic.ContainsKey('isEnabled') | Should -BeTrue
            $Json.triggeringLogic.isEnabled | Should -BeOfType ([bool])
        }

        It 'has triggersOn from the allowed set' {
            $Json.triggeringLogic.ContainsKey('triggersOn') | Should -BeTrue
            $script:ValidTriggersOn | Should -Contain ([string]$Json.triggeringLogic.triggersOn)
        }

        It 'has triggersWhen from the allowed set' {
            $Json.triggeringLogic.ContainsKey('triggersWhen') | Should -BeTrue
            $script:ValidTriggersWhen | Should -Contain ([string]$Json.triggeringLogic.triggersWhen)
        }

        It 'each condition uses a recognised conditionType + operator' -Skip:(-not $Json.triggeringLogic.ContainsKey('conditions')) {
            foreach ($cond in @($Json.triggeringLogic.conditions)) {
                ($cond -is [System.Collections.IDictionary]) | Should -BeTrue
                $cond.ContainsKey('conditionType') | Should -BeTrue
                $script:ValidConditionTypes | Should -Contain ([string]$cond.conditionType)

                if ([string]$cond.conditionType -eq 'Property') {
                    $cond.ContainsKey('conditionProperties') | Should -BeTrue
                    $props = $cond.conditionProperties
                    $props.ContainsKey('propertyName')   | Should -BeTrue
                    $props.ContainsKey('operator')       | Should -BeTrue
                    $script:ValidPropertyOperators | Should -Contain ([string]$props.operator)
                    $props.ContainsKey('propertyValues') | Should -BeTrue
                    ($props.propertyValues -is [System.Collections.IEnumerable] -and -not ($props.propertyValues -is [string])) | Should -BeTrue -Because 'propertyValues must be an array even with one value'
                }
                elseif ([string]$cond.conditionType -eq 'PropertyArrayChanged') {
                    $props = $cond.conditionProperties
                    $script:ValidArrayTypes  | Should -Contain ([string]$props.arrayType)
                    $script:ValidArrayChange | Should -Contain ([string]$props.changeType)
                }
                elseif ([string]$cond.conditionType -eq 'PropertyChanged') {
                    $props = $cond.conditionProperties
                    $script:ValidPropertyChangeTypes | Should -Contain ([string]$props.changeType)
                }
            }
        }
    }

    Context 'actions shape' -Skip:($ParseFailed -or -not ($Json.actions -is [System.Collections.IEnumerable])) {
        It 'every action has a recognised actionType + non-zero order' {
            foreach ($action in @($Json.actions)) {
                ($action -is [System.Collections.IDictionary]) | Should -BeTrue
                $action.ContainsKey('actionType') | Should -BeTrue
                $script:ValidActionTypes | Should -Contain ([string]$action.actionType)
                $action.ContainsKey('order')      | Should -BeTrue
                ($action.order -is [int] -or $action.order -is [long]) | Should -BeTrue
                [int]$action.order | Should -BeGreaterOrEqual 1
            }
        }

        It 'RunPlaybook actions have tenantId + logicAppResourceId' {
            foreach ($action in @($Json.actions)) {
                if ([string]$action.actionType -ne 'RunPlaybook') { continue }
                $cfg = $action.actionConfiguration
                ($cfg -is [System.Collections.IDictionary]) | Should -BeTrue
                $cfg.ContainsKey('tenantId')           | Should -BeTrue
                $cfg.ContainsKey('logicAppResourceId') | Should -BeTrue
                [string]$cfg.tenantId           | Should -Match $script:GuidPattern
                [string]$cfg.logicAppResourceId | Should -Match '^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\.Logic/workflows/[^/]+$' -Because 'logicAppResourceId must be a full ARM resource path'
            }
        }

        It 'AddIncidentTask actions have a title within the documented length budget' {
            foreach ($action in @($Json.actions)) {
                if ([string]$action.actionType -ne 'AddIncidentTask') { continue }
                $cfg = $action.actionConfiguration
                ($cfg -is [System.Collections.IDictionary]) | Should -BeTrue
                $cfg.ContainsKey('title') | Should -BeTrue
                ([string]$cfg.title).Trim() | Should -Not -BeNullOrEmpty
                ([string]$cfg.title).Length | Should -BeLessOrEqual $script:AddIncidentTaskTitleMaxLen -Because "AddIncidentTask.title is capped at $script:AddIncidentTaskTitleMaxLen characters by the Sentinel API"
            }
        }
    }
}

Describe 'Automation rules: cross-file invariants' {
    BeforeAll {
        $repoRoot = Split-Path -Parent $PSScriptRoot
        $rulesRoot = Join-Path $repoRoot 'AutomationRules'

        $script:ruleIdMap = @{}
        if (Test-Path $rulesRoot) {
            Get-ChildItem -Path $rulesRoot -Recurse -Filter '*.json' -File | ForEach-Object {
                try {
                    $j = Get-Content $_.FullName -Raw | ConvertFrom-Json -Depth 32
                    if ($j.PSObject.Properties.Name -notcontains 'automationRuleId') { return }
                    $id = ([string]$j.automationRuleId).ToLowerInvariant()
                    if (-not $script:ruleIdMap.ContainsKey($id)) { $script:ruleIdMap[$id] = @() }
                    $rel = ($_.FullName.Substring($repoRoot.Length + 1)) -replace '\\', '/'
                    $script:ruleIdMap[$id] += $rel
                }
                catch {
                    # Per-file test owns parse errors.
                }
            }
        }
    }

    It 'every automationRuleId is unique across AutomationRules/' {
        $duplicates = $script:ruleIdMap.GetEnumerator() | Where-Object { $_.Value.Count -gt 1 }
        if ($duplicates) {
            $report = ($duplicates | ForEach-Object {
                "  id $($_.Key) used by:`n    - $($_.Value -join "`n    - ")"
            }) -join "`n"
            throw "Duplicate automationRuleId values found (Sentinel uses it as the resource name; collisions silently overwrite):`n$report"
        }
    }
}

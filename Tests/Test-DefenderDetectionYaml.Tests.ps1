#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester 5 schema validation for every YAML in DefenderCustomDetections/.

.DESCRIPTION
    Generates one It block per YAML file via -ForEach so per-file pass/fail
    surfaces directly in the PR check UI rather than collapsing into a
    single combined assertion.

    Schema follows Docs/Content/Defender-Custom-Detections.md and the Graph
    Security custom-detection-rule contract:
    https://learn.microsoft.com/graph/api/resources/security-customdetectionrule

    Cross-file invariant: every rule's `displayName` must be unique across
    the tree (Defender uses display name as the deduplication key on update).

.NOTES
    Run all tests:
        Invoke-Pester -Path Tests/Test-DefenderDetectionYaml.Tests.ps1

    Verbose:
        Invoke-Pester -Path Tests/Test-DefenderDetectionYaml.Tests.ps1 -Output Detailed

    Prerequisites:
        - Pester 5+
        - powershell-yaml (auto-installed by the harness if missing)
#>

BeforeDiscovery {
    $repoRoot = Split-Path -Parent $PSScriptRoot

    if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
        Install-Module -Name powershell-yaml -Force -Scope CurrentUser -AllowClobber | Out-Null
    }
    Import-Module powershell-yaml -ErrorAction Stop

    $script:defenderCases = @()
    $detectionsRoot = Join-Path $repoRoot 'DefenderCustomDetections'
    if (Test-Path $detectionsRoot) {
        $script:defenderCases = @(Get-ChildItem -Path $detectionsRoot -Recurse -Filter '*.yaml' -File | ForEach-Object {
            $rel = ($_.FullName.Substring($repoRoot.Length + 1)) -replace '\\', '/'
            $yaml = $null
            $parseError = $null
            try {
                $raw = Get-Content -Path $_.FullName -Raw -ErrorAction Stop
                if ([string]::IsNullOrWhiteSpace($raw)) { throw 'File is empty' }
                $yaml = ConvertFrom-Yaml $raw
            }
            catch {
                $parseError = $_.Exception.Message
            }

            $period = ''
            if ($yaml -and $yaml.ContainsKey('schedule') -and ($yaml['schedule'] -is [System.Collections.IDictionary]) -and $yaml['schedule'].ContainsKey('period')) {
                $period = [string]$yaml['schedule']['period']
            }

            @{
                Path         = $_.FullName
                RelativePath = $rel
                Yaml         = $yaml
                ParseError   = $parseError
                ParseFailed  = ($null -ne $parseError)
                Period       = $period
                IsNRT        = ($period -eq '0')
            }
        })
    }
}

BeforeAll {
    # Per Docs/Content/Defender-Custom-Detections.md and the Graph Security
    # custom-detection-rule contract.
    $script:DefenderValidSeverities = @('informational', 'low', 'medium', 'high')
    $script:DefenderValidPeriods    = @('0', '1H', '3H', '12H', '24H')

    # The full enum of valid response-action @odata.types and their required-
    # field rules. Keep this aligned with the Complete Action Reference table
    # in Docs/Content/Defender-Custom-Detections.md.
    $script:ResponseActionRequiredFields = @{
        'isolateDeviceResponseAction'                = @('identifier', 'isolationType')
        'collectInvestigationPackageResponseAction'  = @('identifier')
        'runAntivirusScanResponseAction'             = @('identifier')
        'initiateInvestigationResponseAction'        = @('identifier')
        'restrictAppExecutionResponseAction'         = @('identifier')
        'forceUserPasswordResetResponseAction'       = @('identifier')
        'markUserAsCompromisedResponseAction'        = @('identifier')
        'disableUserResponseAction'                  = @('identifier')
        'softDeleteResponseAction'                   = @('identifier')
        'hardDeleteResponseAction'                   = @('identifier')
        'moveToJunkResponseAction'                   = @('identifier')
        'moveToInboxResponseAction'                  = @('identifier')
        'stopAndQuarantineFileResponseAction'        = @('identifier')
        'blockFileResponseAction'                    = @('identifier')
        'allowFileResponseAction'                    = @('identifier')
    }

    # Impacted-asset @odata.types are a smaller fixed enum (device/user/mailbox).
    $script:ImpactedAssetTypes = @(
        '#microsoft.graph.security.impactedDeviceAsset',
        '#microsoft.graph.security.impactedUserAsset',
        '#microsoft.graph.security.impactedMailboxAsset'
    )
}

Describe 'Defender custom detection: <RelativePath>' -ForEach $script:defenderCases {

    It 'parses as valid YAML with a mapping at the root' {
        $ParseError | Should -BeNullOrEmpty
        $Yaml       | Should -Not -BeNullOrEmpty
        ($Yaml -is [System.Collections.IDictionary]) | Should -BeTrue -Because 'Defender detection YAML files must have a mapping at the root'
    }

    Context 'Required top-level fields' -Skip:$ParseFailed {
        It 'has a non-empty displayName' {
            $Yaml.ContainsKey('displayName') | Should -BeTrue
            ([string]$Yaml.displayName).Trim() | Should -Not -BeNullOrEmpty
        }

        It 'has a queryCondition object with a non-empty queryText' {
            $Yaml.ContainsKey('queryCondition') | Should -BeTrue
            ($Yaml.queryCondition -is [System.Collections.IDictionary]) | Should -BeTrue -Because 'queryCondition must be an object'
            $Yaml.queryCondition.ContainsKey('queryText') | Should -BeTrue
            ([string]$Yaml.queryCondition.queryText).Trim() | Should -Not -BeNullOrEmpty
        }

        It 'has a schedule with a valid period' {
            $Yaml.ContainsKey('schedule') | Should -BeTrue
            ($Yaml.schedule -is [System.Collections.IDictionary]) | Should -BeTrue
            $Yaml.schedule.ContainsKey('period') | Should -BeTrue
            $script:DefenderValidPeriods | Should -Contain ([string]$Yaml.schedule.period) -Because "schedule.period must be one of $($script:DefenderValidPeriods -join ', ') (per Docs/Content/Defender-Custom-Detections.md)"
        }

        It 'has detectionAction.alertTemplate as an object' {
            $Yaml.ContainsKey('detectionAction') | Should -BeTrue
            ($Yaml.detectionAction -is [System.Collections.IDictionary]) | Should -BeTrue
            $Yaml.detectionAction.ContainsKey('alertTemplate') | Should -BeTrue
            ($Yaml.detectionAction.alertTemplate -is [System.Collections.IDictionary]) | Should -BeTrue
        }
    }

    Context 'Required alertTemplate fields' -Skip:($ParseFailed -or -not ($Yaml.detectionAction.alertTemplate -is [System.Collections.IDictionary])) {
        It 'has a non-empty alertTemplate.title' {
            $Yaml.detectionAction.alertTemplate.ContainsKey('title') | Should -BeTrue
            ([string]$Yaml.detectionAction.alertTemplate.title).Trim() | Should -Not -BeNullOrEmpty
        }

        It 'has a severity from the allowed set' {
            $Yaml.detectionAction.alertTemplate.ContainsKey('severity') | Should -BeTrue
            $script:DefenderValidSeverities | Should -Contain ([string]$Yaml.detectionAction.alertTemplate.severity) -Because "severity must be one of $($script:DefenderValidSeverities -join ', ') (lowercase, per Docs/Content/Defender-Custom-Detections.md)"
        }

        It 'has a non-empty category' {
            $Yaml.detectionAction.alertTemplate.ContainsKey('category') | Should -BeTrue
            ([string]$Yaml.detectionAction.alertTemplate.category).Trim() | Should -Not -BeNullOrEmpty
        }

        It 'has mitreTechniques as a non-empty list' {
            $Yaml.detectionAction.alertTemplate.ContainsKey('mitreTechniques') | Should -BeTrue
            $techniques = $Yaml.detectionAction.alertTemplate.mitreTechniques
            ($techniques -is [System.Collections.IEnumerable] -and
                -not ($techniques -is [string]) -and
                -not ($techniques -is [System.Collections.IDictionary])) | Should -BeTrue -Because 'mitreTechniques must be a YAML list of T-codes'
            (@($techniques).Count -gt 0) | Should -BeTrue -Because 'mitreTechniques must include at least one technique ID'
        }

        It 'every mitreTechniques entry matches the T-code pattern' {
            foreach ($t in @($Yaml.detectionAction.alertTemplate.mitreTechniques)) {
                ([string]$t) | Should -Match '^T\d{4}(\.\d{3})?$' -Because "MITRE technique IDs follow the pattern Txxxx or Txxxx.yyy (got '$t')"
            }
        }
    }

    Context 'Optional-but-shaped fields' -Skip:$ParseFailed {
        It 'isEnabled is boolean when present' {
            if ($Yaml.ContainsKey('isEnabled')) {
                $Yaml.isEnabled | Should -BeOfType ([bool])
            }
        }

        It 'impactedAssets entries have @odata.type and identifier' -Skip:(-not (($Yaml.detectionAction -is [System.Collections.IDictionary]) -and ($Yaml.detectionAction.alertTemplate -is [System.Collections.IDictionary]) -and $Yaml.detectionAction.alertTemplate.ContainsKey('impactedAssets'))) {
            foreach ($asset in @($Yaml.detectionAction.alertTemplate.impactedAssets)) {
                ($asset -is [System.Collections.IDictionary]) | Should -BeTrue
                $asset.ContainsKey('@odata.type') | Should -BeTrue
                $asset.ContainsKey('identifier')  | Should -BeTrue
                $script:ImpactedAssetTypes | Should -Contain ([string]$asset.'@odata.type') -Because "impactedAssets[].@odata.type must be one of: $($script:ImpactedAssetTypes -join ', ')"
            }
        }

        It 'responseActions entries have a known @odata.type and required fields' -Skip:(-not (($Yaml.detectionAction -is [System.Collections.IDictionary]) -and $Yaml.detectionAction.ContainsKey('responseActions'))) {
            foreach ($action in @($Yaml.detectionAction.responseActions)) {
                ($action -is [System.Collections.IDictionary]) | Should -BeTrue
                $action.ContainsKey('@odata.type') | Should -BeTrue

                $odataType = [string]$action.'@odata.type'
                $odataType | Should -Match '^#microsoft\.graph\.security\.\w+ResponseAction$' -Because "responseAction @odata.type must follow the Graph security namespace pattern (got '$odataType')"

                $actionShortName = $odataType -replace '^#microsoft\.graph\.security\.', ''
                $script:ResponseActionRequiredFields.ContainsKey($actionShortName) | Should -BeTrue -Because "Unknown response action '$actionShortName'. Add to `$script:ResponseActionRequiredFields if this is a new Graph security action."

                foreach ($required in $script:ResponseActionRequiredFields[$actionShortName]) {
                    $action.ContainsKey($required) | Should -BeTrue -Because "responseAction '$actionShortName' requires field '$required' (per Docs/Content/Defender-Custom-Detections.md)"
                }
            }
        }
    }

    Context 'Period-shape rules' -Skip:$ParseFailed {
        It 'NRT rules (period: 0) keep the queryText short enough for real-time evaluation' -Skip:(-not $IsNRT) {
            # Defender NRT rules have an effective KQL line-length budget; this is a
            # soft check against accidentally pasting a 24H-style aggregation query
            # into an NRT slot. 200 lines is the documented practical ceiling.
            $lineCount = ([string]$Yaml.queryCondition.queryText -split "`r?`n").Count
            $lineCount | Should -BeLessOrEqual 200 -Because "NRT rules (period: 0) should keep their KQL under 200 lines for real-time evaluation; this rule has $lineCount lines"
        }
    }
}

Describe 'Defender custom detections: cross-file invariants' {
    BeforeAll {
        # Re-walk under our own BeforeAll so this Describe is self-contained
        # when run alongside other test files via Invoke-PRValidation.ps1
        # (script-scope state from BeforeDiscovery does not survive across
        # Describe boundaries reliably).
        if (-not (Get-Module -Name powershell-yaml)) {
            Import-Module powershell-yaml -ErrorAction Stop
        }
        $repoRoot = Split-Path -Parent $PSScriptRoot
        $detectionsRoot = Join-Path $repoRoot 'DefenderCustomDetections'

        $script:displayNameMap = @{}
        if (Test-Path $detectionsRoot) {
            Get-ChildItem -Path $detectionsRoot -Recurse -Filter '*.yaml' -File | ForEach-Object {
                try {
                    $yaml = ConvertFrom-Yaml (Get-Content $_.FullName -Raw)
                    if (-not $yaml -or -not $yaml.ContainsKey('displayName')) { return }
                    $name = [string]$yaml.displayName
                    if (-not $script:displayNameMap.ContainsKey($name)) { $script:displayNameMap[$name] = @() }
                    $rel = ($_.FullName.Substring($repoRoot.Length + 1)) -replace '\\', '/'
                    $script:displayNameMap[$name] += $rel
                }
                catch {
                    # Per-file schema test owns parse errors; skip silently here.
                }
            }
        }
    }

    It 'every Defender displayName is unique across the tree' {
        $duplicates = $script:displayNameMap.GetEnumerator() | Where-Object { $_.Value.Count -gt 1 }
        if ($duplicates) {
            $report = ($duplicates | ForEach-Object {
                "  '$($_.Key)' used by:`n    - $($_.Value -join "`n    - ")"
            }) -join "`n"
            throw "Duplicate Defender displayName values found (Graph API uses displayName as the upsert key):`n$report"
        }
    }
}

#
# Sentinel-As-Code/Tools/Documenter/Private/Get-SentinelGap.ps1
#
# Created by noodlemctwoodle on 06/05/2026.
#

<#
.SYNOPSIS
    Gap-analysis engine. Loads the best-practices ruleset, builds an in-memory
    Inventory object from the _raw/ JSON files, dispatches each Test-* function and
    aggregates findings.

.DESCRIPTION
    Pure data-in/data-out, testable end-to-end with fixture files.

    Usage:
        $findings = Get-SentinelGap -InputRoot './SecurityDocs/myws/_raw' `
                                    -ResourcesRoot './Tools/Documenter/Private/Resources' `
                                    -RulesPath './Tools/Documenter/Private/Resources/best-practices.json' `
                                    -GapChecksPath './Tools/Documenter/Private/GapChecks.ps1'

    Each finding is a [pscustomobject] with these fields:
        Id           : SENT-001
        Title        : Daily cap not configured...
        Category     : Cost
        Severity     : Warning
        Evidence     : Free-text from the check function
        Detail       : Rule-specific detail object (or $null)
        Remediation  : From best-practices.json
        Learn        : URL from best-practices.json
        CheckName    : Name of the Test-* function
        PassedAt     : ISO-8601 timestamp of the run
#>

function Get-SentinelGap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputRoot,

        [Parameter(Mandatory = $true)]
        [string]$ResourcesRoot,

        [Parameter(Mandatory = $true)]
        [string]$RulesPath,

        [Parameter(Mandatory = $true)]
        [string]$GapChecksPath
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    if (-not (Test-Path $RulesPath))      { throw "Rules file not found: $RulesPath" }
    if (-not (Test-Path $GapChecksPath))  { throw "GapChecks not found: $GapChecksPath" }
    if (-not (Test-Path $InputRoot))      { throw "Input root not found: $InputRoot" }
    if (-not (Test-Path $ResourcesRoot))  { throw "Resources root not found: $ResourcesRoot" }

    # Dot-source the gap check functions into the current scope.
    . $GapChecksPath

    $rules = (Get-Content $RulesPath -Raw | ConvertFrom-Json).rules

    $inventory = New-InventoryFromRaw -InputRoot $InputRoot -ResourcesRoot $ResourcesRoot

    $findings = @()
    foreach ($rule in $rules) {
        $checkName = $rule.check
        $cmd = Get-Command -Name $checkName -CommandType Function -ErrorAction SilentlyContinue
        if (-not $cmd) {
            Write-Warning "Get-SentinelGap: check '$checkName' (rule $($rule.id)) not defined in $GapChecksPath"
            continue
        }

        try {
            $result = & $cmd -Inventory $inventory
        } catch {
            Write-Warning "Get-SentinelGap: rule $($rule.id) ($checkName) threw: $($_.Exception.Message)"
            continue
        }

        if ($null -ne $result) {
            $findings += [pscustomobject]@{
                Id          = $rule.id
                Title       = $rule.title
                Category    = $rule.category
                Severity    = $rule.severity
                Evidence    = $result.Evidence
                Detail      = $result.Detail
                Remediation = $rule.remediation
                Learn       = $rule.learn
                CheckName   = $checkName
                PassedAt    = (Get-Date).ToUniversalTime().ToString('o')
            }
        }
    }

    return ,$findings
}

function New-InventoryFromRaw {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputRoot,

        [Parameter(Mandatory = $true)]
        [string]$ResourcesRoot
    )

    function Read-Json([string]$Name) {
        $p = Join-Path $InputRoot $Name
        if (-not (Test-Path $p)) { return $null }
        $raw = Get-Content $p -Raw
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        return ($raw | ConvertFrom-Json -Depth 32)
    }

    function Read-Resource([string]$Name) {
        $p = Join-Path $ResourcesRoot $Name
        if (-not (Test-Path $p)) { return $null }
        $raw = Get-Content $p -Raw
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        return ($raw | ConvertFrom-Json -Depth 32)
    }

    [pscustomobject]@{
        Workspace              = Read-Json 'workspace.json'
        WorkspaceTables        = @(Read-Json 'workspace-tables.json')
        TablesWithData         = @(Read-Json 'tables-with-data.json')
        Dcrs                   = @(Read-Json 'dcrs.json')
        DiagnosticSettings     = @(Read-Json 'diagnostic-settings.json')
        AlertRules             = @(Read-Json 'alert-rules.json')
        AlertRuleTemplates     = @(Read-Json 'alert-rule-templates.json')
        DataConnectors         = @(Read-Json 'data-connectors-classic.json')
        Settings               = Read-Json  'settings.json'
        UebaDataPresence       = @(Read-Json 'ueba-data-presence.json')
        ContentPackages        = @(Read-Json 'content-packages.json')
        ContentProductPackages = @(Read-Json 'content-product-packages.json')
        DedicatedCluster       = Read-Json 'dedicated-cluster.json'
        ResourceProviders      = @(Read-Json 'resource-providers.json')
        RbacWorkspace          = @(Read-Json 'rbac-workspace.json')
        PlaybookMiAssignments  = @(Read-Json 'rbac-playbook-mi.json')
        IncidentsMttr          = @(Read-Json 'incidents-mttr.json')
        AnalyticsRuleVolumes   = @(Read-Json 'analytics-rule-volumes.json')
        AutomationRules        = @(Read-Json 'automation-rules.json')
        WorkspaceLocks         = @(Read-Json 'workspace-locks.json')
        AmaMmaMigration        = @(Read-Json 'ama-mma-migration.json')
        MitreTactics           = @((Read-Resource 'mitre-attack.json').tactics)
        MitreTechniques        = @((Read-Resource 'mitre-attack.json').techniques)
        SentinelBenefitTables  = Read-Resource 'sentinel-benefit-tables.json'
        CommitmentTiers        = Read-Resource 'commitment-tiers.json'
    }
}

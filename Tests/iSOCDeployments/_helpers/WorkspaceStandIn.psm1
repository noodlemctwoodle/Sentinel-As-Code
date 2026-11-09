#Requires -Version 7.6

<#
.SYNOPSIS
    A stand-in subscription for Get-iSOCWorkspaceOnboarding and the
    workspace setting type, and the reader that lifts the inline PowerShell
    they replace out of the deploy pipelines.

.DESCRIPTION
    Get-WorkspaceStandIn builds the state: resource groups, workspaces, the
    two Sentinel onboarding resources per workspace, the workspace's
    settings with their etags, settings whose write is refused (403) or
    rejected (400), and paths whose read is refused.

    Invoke-WorkspaceStandInArm answers one ARM request and records every
    read and write in the state's Reads and Writes, in order. The
    pipelines' stand-in Az cmdlets (in a child pwsh, through
    Export-WorkspaceStandIn and Import-WorkspaceStandIn) and the module's
    mocked REST client both call it, so both read and change one
    subscription.

    Read-PipelineYaml parses a pipeline file, Get-PipelineStep returns the
    steps it runs with given parameters (the ${{ if }}, ${{ elseif }} and
    ${{ else }} insertions on eq and ne of a parameter evaluated), and
    Get-PipelineInlineScript returns the inline script of one of those
    steps, with its pipeline variables put in. Deploy-iSOCWorkspace's
    suite and Pipelines.Tests.ps1 use them.

.NOTES
    File:         Tests/iSOCDeployments/_helpers/WorkspaceStandIn.psm1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.3.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+, powershell-yaml
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-WorkspaceStandIn {
    <# The default: rg-sentinel with law-sentinel, fully onboarded, and rg-playbooks; no settings yet. #>
    param(
        [string[]] $ResourceGroups = @('rg-sentinel', 'rg-playbooks'),
        [string[]] $Workspaces = @('rg-sentinel/law-sentinel'),
        [string[]] $Solutions = @('rg-sentinel/law-sentinel'),
        [string[]] $Onboarded = @('rg-sentinel/law-sentinel'),
        [hashtable] $Settings = @{},
        [string[]] $Denied = @(),
        [string[]] $Failing = @(),
        [string[]] $Forbidden = @()
    )

    $existing = [ordered]@{}
    foreach ($name in @($Settings.Keys | Sort-Object)) { $existing[$name] = [ordered]@{ etag = [string]$Settings[$name] } }
    [ordered]@{
        SubscriptionId = '11111111-2222-3333-4444-555555555555'
        ResourceGroups = @($ResourceGroups)
        Workspaces     = @($Workspaces)
        Solutions      = @($Solutions)
        Onboarded      = @($Onboarded)
        Settings       = $existing
        Denied         = @($Denied)
        Failing        = @($Failing)
        Forbidden      = @($Forbidden)
        Reads          = @()
        Writes         = @()
    }
}

function Export-WorkspaceStandIn {
    param($State, [string] $Path)
    $State | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding utf8NoBOM
}

function Import-WorkspaceStandIn {
    param([string] $Path)
    $raw = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
    $state = [ordered]@{}
    foreach ($key in 'SubscriptionId', 'ResourceGroups', 'Workspaces', 'Solutions', 'Onboarded', 'Settings', 'Denied', 'Failing', 'Forbidden', 'Reads', 'Writes') {
        $state[$key] = $raw[$key]
    }
    foreach ($key in 'ResourceGroups', 'Workspaces', 'Solutions', 'Onboarded', 'Denied', 'Failing', 'Forbidden', 'Reads', 'Writes') { $state[$key] = @($state[$key] | Where-Object { $null -ne $_ }) }
    if ($null -eq $state.Settings) { $state.Settings = [ordered]@{} }
    $state
}

function Invoke-WorkspaceStandInArm {
    <# One ARM request; returns @{ Status; Body } with Body a JSON-ready object. Path without host; any query is ignored. #>
    param($State, [string] $Method, [string] $Path, $Body)

    $p = ($Path -replace '^https?://[^/]+', '' -split '\?')[0]
    $sub = [regex]::Escape("/subscriptions/$($State.SubscriptionId)")
    $notFound = @{ Status = 404; Body = [ordered]@{ error = [ordered]@{ code = 'ResourceNotFound'; message = "The resource $p was not found." } } }

    if ($Method -eq 'GET') { $State.Reads = @($State.Reads) + @($p) }
    if ($State.Forbidden -contains $p) {
        return @{ Status = 403; Body = [ordered]@{ error = [ordered]@{ code = 'AuthorizationFailed'; message = "The client does not have authorization to perform action 'read' over scope '$p'." } } }
    }

    if ($Method -eq 'GET' -and $p -match "^$sub/resourceGroups/([^/]+)$") {
        if ($State.ResourceGroups -cnotcontains $Matches[1]) { return $notFound }
        return @{ Status = 200; Body = [ordered]@{ id = $p; name = $Matches[1]; location = 'uksouth' } }
    }
    if ($Method -eq 'GET' -and $p -match "^$sub/resourceGroups/([^/]+)/providers/Microsoft\.OperationalInsights/workspaces/([^/]+)$") {
        if ($State.Workspaces -cnotcontains "$($Matches[1])/$($Matches[2])") { return $notFound }
        return @{ Status = 200; Body = [ordered]@{ id = $p; name = $Matches[2]; location = 'uksouth'; properties = [ordered]@{ customerId = 'cccccccc-0000-0000-0000-000000000001' } } }
    }
    if ($Method -eq 'GET' -and $p -match "^$sub/resourceGroups/([^/]+)/providers/Microsoft\.OperationsManagement/solutions/SecurityInsights\(([^/]+)\)$") {
        if ($State.Solutions -cnotcontains "$($Matches[1])/$($Matches[2])") { return $notFound }
        return @{ Status = 200; Body = [ordered]@{ id = $p; name = "SecurityInsights($($Matches[2]))"; properties = [ordered]@{ provisioningState = 'Succeeded' } } }
    }
    if ($Method -eq 'GET' -and $p -match "^$sub/resourceGroups/([^/]+)/providers/Microsoft\.OperationalInsights/workspaces/([^/]+)/providers/Microsoft\.SecurityInsights/onboardingStates/default$") {
        if ($State.Onboarded -cnotcontains "$($Matches[1])/$($Matches[2])") { return $notFound }
        return @{ Status = 200; Body = [ordered]@{ id = $p; name = 'default'; properties = [ordered]@{} } }
    }
    if ($p -match "^$sub/resourceGroups/[^/]+/providers/Microsoft\.OperationalInsights/workspaces/[^/]+/providers/Microsoft\.SecurityInsights/settings/([^/]+)$") {
        $name = $Matches[1]
        if ($Method -eq 'GET') {
            if (-not $State.Settings.Contains($name)) { return $notFound }
            return @{ Status = 200; Body = [ordered]@{ id = $p; name = $name; etag = $State.Settings[$name].etag; kind = $name; properties = [ordered]@{} } }
        }
        if ($Method -eq 'PUT') {
            $sent = if ($Body -is [string]) { $Body | ConvertFrom-Json -AsHashtable } else { $Body | ConvertTo-Json -Depth 20 | ConvertFrom-Json -AsHashtable }
            $State.Writes = @($State.Writes) + @([ordered]@{ Kind = 'Put'; Path = $p; Name = $name; Body = $sent })
            if ($State.Denied -contains $name) {
                return @{ Status = 403; Body = [ordered]@{ error = [ordered]@{ code = 'Forbidden'; message = "The client does not have permission to change the $name setting." } } }
            }
            if ($State.Failing -contains $name) {
                return @{ Status = 400; Body = [ordered]@{ error = [ordered]@{ code = 'BadRequest'; message = "The $name setting is not valid for this workspace." } } }
            }
            $etag = "W/`"$name-$(@($State.Writes).Count)`""
            $State.Settings[$name] = [ordered]@{ etag = $etag }
            return @{ Status = 200; Body = [ordered]@{ id = $p; name = $name; etag = $etag; kind = $sent['kind']; properties = $sent['properties'] } }
        }
    }
    throw "The stand-in has no answer for $Method $p"
}

function Read-PipelineYaml {
    <# The parsed pipeline file. #>
    param([string] $Path)
    Import-Module powershell-yaml -ErrorAction Stop
    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Yaml
}

function Resolve-PipelineParameter {
    <#
    The value of every parameter a pipeline declares: its default, or the
    value $Parameters gives it. A name the pipeline does not declare, or a
    value outside the parameter's values list, is an error, as Azure DevOps
    makes it when the run is queued.
    #>
    param([System.Collections.IDictionary] $Yaml, [hashtable] $Parameters = @{})

    $values = @{}
    $declared = @{}
    if ($Yaml.Contains('parameters')) {
        foreach ($parameter in @($Yaml.parameters)) {
            $declared[$parameter.name] = $parameter
            $values[$parameter.name] = $parameter['default']
        }
    }
    foreach ($name in $Parameters.Keys) {
        if (-not $declared.ContainsKey($name)) { throw "The pipeline declares no parameter '$name'." }
        $allowed = $declared[$name]['values']
        if ($allowed -and @($allowed) -notcontains $Parameters[$name]) { throw "'$($Parameters[$name])' is not one of the values of the parameter '$name': $(@($allowed) -join ', ')." }
        $values[$name] = $Parameters[$name]
    }
    $values
}

function Test-PipelineCondition {
    <#
    Evaluate a template condition of the form eq(parameters.name, 'value')
    or ne(...), with a quoted string or true/false. Strings compare without
    case, as Azure DevOps compares them. Any other condition is an error,
    so a pipeline that gains one fails the test rather than being read
    wrongly.
    #>
    param([string] $Condition, [hashtable] $Values)

    $m = [regex]::Match($Condition.Trim(), '^(?<op>eq|ne)\(\s*parameters\.(?<name>\w+)\s*,\s*(?:''(?<text>[^'']*)''|(?<bool>true|false))\s*\)$')
    if (-not $m.Success) { throw "The test cannot evaluate the template condition '$Condition'." }
    $name = $m.Groups['name'].Value
    if (-not $Values.ContainsKey($name)) { throw "The condition '$Condition' names the parameter '$name', which the pipeline does not declare." }
    $actual = $Values[$name]
    $equal = if ($m.Groups['bool'].Success) { [bool]$actual -eq [bool]::Parse($m.Groups['bool'].Value) } else { [string]$actual -eq $m.Groups['text'].Value }
    if ($m.Groups['op'].Value -eq 'eq') { $equal } else { -not $equal }
}

function Expand-PipelineSequence {
    <#
    The items of a stages, jobs or steps list after template insertion:
    an item that is only ${{ if c }}, ${{ elseif c }} or ${{ else }} is
    replaced by its own items when its branch is taken, and dropped when it
    is not.
    #>
    param([object[]] $Items, [hashtable] $Values)

    $chain = $null
    foreach ($item in $Items) {
        if ($item -is [System.Collections.IDictionary] -and $item.Count -eq 1) {
            $key = [string]@($item.Keys)[0]
            $m = [regex]::Match($key, '^\$\{\{\s*(?<kind>if|elseif|else)\b(?<condition>.*?)\s*\}\}$')
            if ($m.Success) {
                $take = $false
                switch ($m.Groups['kind'].Value) {
                    'if' {
                        $take = Test-PipelineCondition -Condition $m.Groups['condition'].Value -Values $Values
                        $chain = $take
                    }
                    'elseif' {
                        if ($null -eq $chain) { throw "An `${{ elseif }} follows no `${{ if }}: $key" }
                        if (-not $chain) {
                            $take = Test-PipelineCondition -Condition $m.Groups['condition'].Value -Values $Values
                            $chain = $take
                        }
                    }
                    'else' {
                        if ($null -eq $chain) { throw "An `${{ else }} follows no `${{ if }}: $key" }
                        $take = -not $chain
                        $chain = $null
                    }
                }
                if ($take) { Expand-PipelineSequence -Items @($item[$key]) -Values $Values }
                continue
            }
            if ($key.StartsWith('${{')) { throw "The test cannot expand the template expression '$key'." }
        }
        $chain = $null
        $item
    }
}

function Get-PipelineStep {
    <#
    Every step of a pipeline file, in order, after template insertion with
    the pipeline's parameter defaults and the values $Parameters gives.
    Each step carries the stage and job it is in, as PipelineStage and
    PipelineJob keys (null in a GitHub workflow's stage).
    #>
    param([string] $Path, [hashtable] $Parameters = @{})

    $yaml = Read-PipelineYaml -Path $Path
    $values = Resolve-PipelineParameter -Yaml $yaml -Parameters $Parameters
    if ($yaml.Contains('stages')) {
        foreach ($stage in (Expand-PipelineSequence -Items @($yaml.stages) -Values $values)) {
            foreach ($job in (Expand-PipelineSequence -Items @($stage.jobs) -Values $values)) {
                foreach ($step in (Expand-PipelineSequence -Items @($job.steps) -Values $values)) {
                    if ($step -is [System.Collections.IDictionary]) { $step['PipelineStage'] = $stage.stage; $step['PipelineJob'] = $job.job }
                    $step
                }
            }
        }
    }
    else {
        foreach ($jobName in $yaml.jobs.Keys) {
            foreach ($step in (Expand-PipelineSequence -Items @($yaml.jobs[$jobName].steps) -Values $values)) {
                if ($step -is [System.Collections.IDictionary]) { $step['PipelineStage'] = $null; $step['PipelineJob'] = $jobName }
                $step
            }
        }
    }
}

function Get-PipelineStage {
    <#
    The stages of an Azure DevOps pipeline file after template insertion
    with the parameter defaults and $Parameters, each with its dependsOn
    list expanded too (as an array, empty when it has none).
    #>
    param([string] $Path, [hashtable] $Parameters = @{})

    $yaml = Read-PipelineYaml -Path $Path
    $values = Resolve-PipelineParameter -Yaml $yaml -Parameters $Parameters
    foreach ($stage in (Expand-PipelineSequence -Items @($yaml.stages) -Values $values)) {
        $stage['dependsOn'] = if ($stage.Contains('dependsOn')) { @(Expand-PipelineSequence -Items @($stage.dependsOn) -Values $values) } else { @() }
        $stage
    }
}

function Get-PipelineVariableValue {
    <#
    The compile-time value of each variable an Azure DevOps pipeline file
    declares in its top-level variables list, by name: a value, or the
    ${{ if }} / ${{ else }} branch its parameters take. Variable groups are
    left out.
    #>
    param([string] $Path, [hashtable] $Parameters = @{})

    $yaml = Read-PipelineYaml -Path $Path
    $values = Resolve-PipelineParameter -Yaml $yaml -Parameters $Parameters
    $result = @{}
    foreach ($variable in @($yaml.variables)) {
        if (-not $variable.Contains('name')) { continue }
        if ($variable.Contains('value')) { $result[$variable.name] = [string]$variable.value; continue }
        $branch = @($variable.Keys | Where-Object { $_ -match '^\$\{\{\s*if\s+.+\}\}$' })
        if ($branch.Count -ne 1) { throw "The test cannot read the variable '$($variable.name)'." }
        $condition = [regex]::Match($branch[0], '^\$\{\{\s*if\s+(.+?)\s*\}\}$').Groups[1].Value
        $result[$variable.name] = if (Test-PipelineCondition -Condition $condition -Values $values) { [string]$variable[$branch[0]].value } else { [string]$variable['${{ else }}'].value }
    }
    $result
}

function Get-PipelineInlineScript {
    <#
    Return the inline PowerShell of the step named $Step (an ADO step's
    displayName, a GitHub step's name) in a pipeline file, with each of its
    pipeline variables replaced by the value $Variables gives it by name:
    ADO macros $(name) for the deployment variables, $(Build.SourcesDirectory)
    and the flag variables; GitHub and ADO template expressions
    ${{ env|vars|secrets|inputs|parameters|github.NAME }}, with a
    || 'literal' default taken when the value is empty or false. A variable
    it uses that $Variables does not name, or any other template
    expression, is an error, so a step that gains one fails the test rather
    than running with the macro in its text. The steps are the ones the
    pipeline runs with $Parameters (Get-PipelineStep).
    #>
    param([string] $Path, [string] $Step, [hashtable] $Variables, [hashtable] $Parameters = @{})

    $steps = Get-PipelineStep -Path $Path -Parameters $Parameters
    $found = @($steps | Where-Object { $_ -is [System.Collections.IDictionary] -and ($_['displayName'] -eq $Step -or $_['name'] -eq $Step) })
    if ($found.Count -ne 1) { throw "Found $($found.Count) steps named '$Step' in $Path." }
    $inputs = if ($found[0].Contains('inputs')) { $found[0].inputs } elseif ($found[0].Contains('with')) { $found[0].with } else { @{} }
    $script = if ($inputs.Contains('Inline')) { $inputs.Inline } elseif ($inputs.Contains('inlineScript')) { $inputs.inlineScript } elseif ($inputs.Contains('script')) { $inputs.script } else { $found[0].run }

    $values = $Variables
    $macro = '\$\{\{\s*(?:env|vars|secrets|inputs|parameters|github)\.(?<name>\w+)\s*(?:\|\|\s*''(?<default>[^'']*)''\s*)?\}\}|\$\((?<name>azureSubscriptionId|sentinelResourceGroup|sentinelWorkspaceName|playbookResourceGroup|sentinelRegion|Build\.SourcesDirectory|flag\w+)\)'
    $text = [regex]::Replace($script, $macro, {
            param($m)
            $name = $m.Groups['name'].Value
            if (-not $values.ContainsKey($name)) { throw "The step '$Step' uses the pipeline variable '$name', which the test does not give." }
            $value = [string]$values[$name]
            if ($m.Groups['default'].Success -and ($value -eq '' -or $value -eq 'false')) { $value = $m.Groups['default'].Value }
            $value
        })
    if ($text.Contains('${{')) { throw "The step '$Step' has a template expression the test cannot fill in: $(([regex]::Match($text, '\$\{\{[^}]*\}\}')).Value)" }
    $text
}

Export-ModuleMember -Function Get-WorkspaceStandIn, Export-WorkspaceStandIn, Import-WorkspaceStandIn, Invoke-WorkspaceStandInArm, Read-PipelineYaml, Resolve-PipelineParameter, Test-PipelineCondition, Get-PipelineStep, Get-PipelineStage, Get-PipelineVariableValue, Get-PipelineInlineScript

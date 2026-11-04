#Requires -Version 7.2

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

    Get-PipelineInlineScript returns the inline script of one step of a
    pipeline file, with its pipeline variables put in.

.NOTES
    File:         Tests/iSOCDeployments/_helpers/WorkspaceStandIn.psm1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.0
    Last Updated: 2026-11-04
    Requires:     PowerShell 7.2+, powershell-yaml
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

function Get-PipelineInlineScript {
    <#
    Return the inline PowerShell of the step named $Step (an ADO step's
    displayName, a GitHub step's name) in a pipeline file, with each of its
    pipeline variables replaced by the value $Variables gives it by name
    (ADO $(name), GitHub ${{ env.NAME }}, ${{ vars.NAME }} or
    ${{ secrets.NAME }}). A variable it uses that $Variables does not name
    is an error, so a step that gains one fails the test rather than
    running with the macro in its text.
    #>
    param([string] $Path, [string] $Step, [hashtable] $Variables)

    Import-Module powershell-yaml -ErrorAction Stop
    $yaml = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Yaml
    $steps = if ($yaml.Contains('stages')) {
        foreach ($stage in $yaml.stages) { foreach ($job in @($stage.jobs)) { @($job.steps) } }
    }
    else {
        foreach ($job in $yaml.jobs.Values) { @($job.steps) }
    }
    $found = @($steps | Where-Object { $_ -is [System.Collections.IDictionary] -and ($_['displayName'] -eq $Step -or $_['name'] -eq $Step) })
    if ($found.Count -ne 1) { throw "Found $($found.Count) steps named '$Step' in $Path." }
    $inputs = if ($found[0].Contains('inputs')) { $found[0].inputs } else { $found[0].with }
    $script = if ($inputs.Contains('Inline')) { $inputs.Inline } else { $inputs.inlineScript }

    $values = $Variables
    $macro = '\$\{\{\s*(?:env|vars|secrets)\.(?<name>\w+)\s*\}\}|\$\((?<name>azureSubscriptionId|sentinelResourceGroup|sentinelWorkspaceName|playbookResourceGroup|sentinelRegion)\)'
    [regex]::Replace($script, $macro, {
            param($m)
            $name = $m.Groups['name'].Value
            if (-not $values.ContainsKey($name)) { throw "The step '$Step' uses the pipeline variable '$name', which the test does not give." }
            [string]$values[$name]
        })
}

Export-ModuleMember -Function Get-WorkspaceStandIn, Export-WorkspaceStandIn, Import-WorkspaceStandIn, Invoke-WorkspaceStandInArm, Get-PipelineInlineScript

#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Checks every command call in the SharePoint site scripts against the
    real parameter metadata of the PnP.PowerShell version the pipelines pin.

.DESCRIPTION
    The publisher only meets SharePoint in a pipeline run, so a call that
    cannot bind (an unknown parameter, or two parameters that sit in
    different parameter sets) used to surface one run at a time. This suite
    parses Modules/iSOCBlueprint/Engine/SharePoint/*.ps1 and Private/*.ps1 and, for each
    call to a PnP.PowerShell cmdlet or to one of the scripts' own functions,
    checks that:

      - every named parameter exists (by name, alias or unique prefix);
      - at least one parameter set takes all of them together;
      - that set's mandatory parameters are supplied, by name, by position
        or from the pipeline;
      - Remove-PnP* calls pass -Force, so no confirmation prompt can stop a
        non-interactive run (Remove-PnPApp is exempt: it prompts only to
        enable scripting on a no-script site, which needs an admin anyway).

    It also flags calls to *-PnP* or *-Sac* commands that do not exist.
    Splatted calls and cmdlets with dynamic parameters are not judged.

    A second check follows each entry script (publish, bootstrap, build)
    through the files it dot-sources and fails when it calls a function
    none of them defines: the binding check loads every file together, so
    it cannot see a file the publisher forgot to load.

    The PnP.PowerShell version is read from the pnpVersion variable in
    Pipelines/Sentinel-Blueprint.yml. Both PR validation jobs install that
    version, and in CI (TF_BUILD or GITHUB_ACTIONS set) a missing version
    fails the suite. Locally the suite is skipped without it
    (Install-Module PnP.PowerShell -RequiredVersion <version> -Scope
    CurrentUser to run it).

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCBlueprint/SharePoint-PnPCalls.Tests.ps1 -Output Detailed

.NOTES
    File:         Tests/iSOCBlueprint/SharePoint-PnPCalls.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-12
    Version:      0.3.1
    Last Updated: 2026-10-13
    Requires:     PowerShell 7.4+, Pester 5+, PnP.PowerShell (pinned version)
#>

BeforeDiscovery {
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $pipeline = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'Pipelines/Sentinel-Blueprint.yml')
    $script:pnpVersion = if ($pipeline -match '(?m)-\s*name:\s*pnpVersion\s*\r?\n\s*value:\s*"?(?<v>[\d.]+)"?') { $Matches['v'] } else { '' }
    $script:pnpAvailable = [bool]($script:pnpVersion -and (Get-Module -ListAvailable -Name PnP.PowerShell | Where-Object { [string]$_.Version -eq $script:pnpVersion }))
    $script:inCi = [bool]($env:TF_BUILD -or $env:GITHUB_ACTIONS)
    $sp = Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/SharePoint'
    $script:scriptFiles = @(
        Get-ChildItem -LiteralPath $sp -Filter '*.ps1' -File
        Get-ChildItem -LiteralPath (Join-Path $sp 'Private') -Filter '*.ps1' -File
    ) | ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } }
}

Describe 'PnP.PowerShell calls in the SharePoint scripts' -Skip:(-not $script:pnpAvailable -and -not $script:inCi) {

    BeforeAll {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $pipeline = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'Pipelines/Sentinel-Blueprint.yml')
        $null = $pipeline -match '(?m)-\s*name:\s*pnpVersion\s*\r?\n\s*value:\s*"?(?<v>[\d.]+)"?'
        $script:pinnedPnP = $Matches['v']
        $script:pnpReady = [bool](Get-Module -ListAvailable -Name PnP.PowerShell | Where-Object { [string]$_.Version -eq $script:pinnedPnP })
        if ($script:pnpReady) { Import-Module PnP.PowerShell -RequiredVersion $script:pinnedPnP -ErrorAction Stop }

        # The scripts' own functions, and the Blueprint helpers the build
        # script uses, defined in a throwaway module so Get-Command sees
        # their parameters. Only definitions are evaluated, no script body.
        $sp = Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/SharePoint'
        $sources = @(
            Get-ChildItem -LiteralPath $sp -Filter '*.ps1' -File
            Get-ChildItem -LiteralPath (Join-Path $sp 'Private') -Filter '*.ps1' -File
            Get-ChildItem -LiteralPath (Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/Private') -Filter '*.ps1' -File
        )
        $definitions = foreach ($file in $sources) {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null)
            $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false) | ForEach-Object { $_.Extent.Text }
        }
        $script:defsModule = New-Module -Name SacCallCheck -ScriptBlock ([scriptblock]::Create(($definitions -join "`n`n") + "`nExport-ModuleMember -Function *")) |
            Import-Module -PassThru -Force

        $common = [System.Management.Automation.Cmdlet]::CommonParameters + [System.Management.Automation.Cmdlet]::OptionalCommonParameters

        function Test-SacCommandCall {
            param([string] $Path)
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
            foreach ($cmd in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true)) {
                $name = $cmd.GetCommandName()
                if (-not $name) { continue }
                $at = "line $($cmd.Extent.StartLineNumber): $name"
                $info = Get-Command -Name $name -ErrorAction SilentlyContinue | Select-Object -First 1
                if (-not $info) {
                    if ($name -match '-(PnP|Sac)') { "$at does not exist" }
                    continue
                }
                if ($info.CommandType -eq 'Alias') { $info = $info.ResolvedCommand }
                if ($info.CommandType -eq 'Application' -or -not $info.Parameters) { continue }
                if ($info.Source -ne 'PnP.PowerShell' -and $info.Source -ne 'SacCallCheck') { continue }
                $dynamic = $info.PSObject.Properties['ImplementingType'] -and $info.ImplementingType -and
                    [System.Management.Automation.IDynamicParameters].IsAssignableFrom($info.ImplementingType)

                $keys = @($info.Parameters.Keys)
                $used = [System.Collections.Generic.List[string]]::new()
                $positional = 0
                $splatted = $false
                $unknown = $false
                $elements = $cmd.CommandElements
                for ($i = 1; $i -lt $elements.Count; $i++) {
                    $el = $elements[$i]
                    if ($el -is [System.Management.Automation.Language.CommandParameterAst]) {
                        $p = $el.ParameterName
                        $match = @($keys | Where-Object { $_ -eq $p })
                        if (-not $match) { $match = @($keys | Where-Object { @($info.Parameters[$_].Aliases) -contains $p }) }
                        if (-not $match) { $match = @($keys | Where-Object { $_ -like "$p*" }) }
                        if ($match.Count -ne 1) {
                            if (-not $dynamic) { "$at has no parameter -$p" }
                            $unknown = $true
                            continue
                        }
                        $full = [string]$match[0]
                        $used.Add($full)
                        if (-not $info.Parameters[$full].SwitchParameter -and -not $el.Argument) { $i++ }
                    }
                    elseif ($el -is [System.Management.Automation.Language.VariableExpressionAst] -and $el.Splatted) { $splatted = $true }
                    else { $positional++ }
                }
                if ($splatted -or $unknown) { continue }

                if ($name -like 'Remove-PnP*' -and $name -ne 'Remove-PnPApp' -and $info.Parameters.ContainsKey('Force') -and 'Force' -notin $used) {
                    "$at does not pass -Force, so it can prompt in a pipeline"
                }

                $nonCommon = @($used | Where-Object { $_ -notin $common })
                $fromPipeline = $cmd.Parent -is [System.Management.Automation.Language.PipelineAst] -and $cmd.Parent.PipelineElements.IndexOf($cmd) -gt 0
                $sets = @($info.ParameterSets)
                $candidates = @($sets | Where-Object { $names = $_.Parameters.Name; @($nonCommon | Where-Object { $_ -notin $names }).Count -eq 0 })
                if ($candidates.Count -eq 0) {
                    "$at combines $($nonCommon -join ', '), which no parameter set takes together"
                    continue
                }
                $satisfied = @($candidates | Where-Object {
                        $missing = @($_.Parameters | Where-Object {
                                $_.IsMandatory -and $_.Name -notin $used -and
                                -not ($fromPipeline -and ($_.ValueFromPipeline -or $_.ValueFromPipelineByPropertyName))
                            })
                        $byPosition = @($missing | Where-Object { $_.Position -ge 0 })
                        $missing.Count -eq $byPosition.Count -and $byPosition.Count -le $positional
                    })
                if ($satisfied.Count -eq 0) {
                    "$at is missing a mandatory parameter (" + (($candidates | ForEach-Object {
                                "$($_.Name): " + ((@($_.Parameters | Where-Object { $_.IsMandatory -and $_.Name -notin $used }).Name) -join ', ')
                            }) -join '; ') + ')'
                }
                elseif ($satisfied.Count -gt 1 -and $sets.Count -gt 1 -and -not ($satisfied | Where-Object IsDefault)) {
                    "$at matches more than one parameter set ($(($satisfied.Name) -join ', '))"
                }
            }
        }
    }

    AfterAll {
        if ($script:defsModule) { Remove-Module -ModuleInfo $script:defsModule -Force -ErrorAction SilentlyContinue }
    }

    It 'has the pinned PnP.PowerShell installed' {
        $script:pnpReady | Should -BeTrue -Because "the PR validation job installs PnP.PowerShell $script:pinnedPnP (pnpVersion in Pipelines/Sentinel-Blueprint.yml)"
    }

    It 'every call in <Name> binds' -ForEach $script:scriptFiles {
        if (-not $script:pnpReady) { Set-ItResult -Skipped -Because "PnP.PowerShell $script:pinnedPnP is not installed"; return }
        $problems = @(Test-SacCommandCall -Path $Path)
        $problems | Should -BeNullOrEmpty -Because ("in ${Name}:`n  " + ($problems -join "`n  "))
    }
}

Describe 'Commands the SharePoint entry scripts call are loaded by them' -Skip:(-not $script:pnpAvailable -and -not $script:inCi) {

    BeforeAll {
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:spRoot = Join-Path $repoRoot 'Modules/iSOCBlueprint/Engine/SharePoint'
        $pipeline = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'Pipelines/Sentinel-Blueprint.yml')
        $null = $pipeline -match '(?m)-\s*name:\s*pnpVersion\s*\r?\n\s*value:\s*"?(?<v>[\d.]+)"?'
        $script:pinned = $Matches['v']
        $script:ready = [bool](Get-Module -ListAvailable -Name PnP.PowerShell | Where-Object { [string]$_.Version -eq $script:pinned })
        if ($script:ready) { Import-Module PnP.PowerShell -RequiredVersion $script:pinned -ErrorAction Stop }

        # The files an entry script loads: itself and everything it
        # dot-sources as '. (Join-Path $PSScriptRoot '<path>')', followed
        # through each loaded file in turn.
        function Get-SacLoadedFile([string]$Path, [System.Collections.Generic.HashSet[string]]$Seen) {
            $full = (Resolve-Path -LiteralPath $Path).Path
            if (-not $Seen.Add($full)) { return }
            $full
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($full, [ref]$null, [ref]$null)
            foreach ($c in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] -and $args[0].InvocationOperator -eq 'Dot' }, $true)) {
                if ($c.CommandElements[0].Extent.Text -match "Join-Path \`$PSScriptRoot '([^']+)'") {
                    Get-SacLoadedFile -Path (Join-Path (Split-Path $full) $Matches[1]) -Seen $Seen
                }
            }
        }
    }

    # Each script runs on its own in a pipeline, so a function defined in a
    # file it does not load fails only there (as ConvertTo-SacChartFallbackHtml
    # once did in the publisher). The binding suite above loads every file
    # together and cannot see that.
    It '<_> defines or imports every command it calls' -ForEach @('Publish-SentinelDocsSite.ps1', 'Initialize-SentinelDocsSite.ps1', 'Build-SentinelDocsSite.ps1') {
        if (-not $script:ready) { Set-ItResult -Skipped -Because "PnP.PowerShell $script:pinned is not installed"; return }
        $files = @(Get-SacLoadedFile -Path (Join-Path $script:spRoot $_) -Seen ([System.Collections.Generic.HashSet[string]]::new()))
        $defined = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $calls = @{}
        foreach ($f in $files) {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$null, [ref]$null)
            foreach ($d in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) { [void]$defined.Add($d.Name) }
            foreach ($c in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true)) {
                $n = $c.GetCommandName()
                if ($n -and -not $calls.ContainsKey($n)) { $calls[$n] = "$(Split-Path $f -Leaf):$($c.Extent.StartLineNumber)" }
            }
        }
        $missing = @($calls.Keys | Where-Object { -not $defined.Contains($_) -and -not (Get-Command $_ -ErrorAction SilentlyContinue) } | Sort-Object | ForEach-Object { "$_ ($($calls[$_]))" })
        $missing | Should -BeNullOrEmpty -Because "$_ loads $(($files | ForEach-Object { Split-Path $_ -Leaf }) -join ', ')"
    }
}

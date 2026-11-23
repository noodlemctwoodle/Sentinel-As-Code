#Requires -Version 7.6

<#
.SYNOPSIS
    Resolve a criterion's source to Met, Gap or Unknown.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Maturity/Criteria/Resolve-MaturitySource.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.2
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Maturity Engine
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Resolve-MaturitySource {
    <#
    .SYNOPSIS
        Resolve one source (recursively for allOf / anyOf) to Met, Gap or
        Unknown, with the metric value and the rule evidence that decided it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] $Source,
        [Parameter(Mandatory = $true)] $Metrics,
        [Parameter(Mandatory = $true)] [hashtable] $OutcomeById,
        [Parameter(Mandatory = $true)] [hashtable] $EvidenceById
    )
    $kind = [string](Get-MaturityPropertyValue $Source 'kind' '')
    switch ($kind) {
        'gapRule' {
            $rule = [string](Get-MaturityPropertyValue $Source 'rule' '')
            $outcome = if ($OutcomeById.ContainsKey($rule)) { $OutcomeById[$rule] } else { $null }
            $status = switch ($outcome) { 'Passed' { 'Met' } 'Fired' { 'Gap' } default { 'Unknown' } }
            $evidence = $null
            if ($status -eq 'Gap' -and $EvidenceById.ContainsKey($rule)) { $evidence = $EvidenceById[$rule] }
            elseif ($status -eq 'Unknown') { $evidence = "$rule was not evaluated in this run." }
            return [pscustomobject]@{ Status = $status; Metric = $null; Rule = $rule; Evidence = $evidence }
        }
        'metric' {
            $path = [string](Get-MaturityPropertyValue $Source 'path' '')
            $value = $Metrics[$path]
            if ($null -eq $value) {
                return [pscustomobject]@{
                    Status = 'Unknown'
                    Metric = $null
                    Rule = $null
                    Evidence = "Metric '$path' has no value in this run (not captured, or nothing to measure)."
                }
            }
            $expected = Get-MaturityPropertyValue $Source 'value' $null
            $op = [string](Get-MaturityPropertyValue $Source 'op' '')
            $pass = if ($expected -is [bool]) {
                ([bool]$value) -eq $expected
            } else {
                $left = ConvertTo-MaturityNumber $value; $right = ConvertTo-MaturityNumber $expected
                switch ($op) {
                    'gt' {
                        $left -gt $right
                    } 'ge' { $left -ge $right } 'eq' { $left -eq $right } 'lt' { $left -lt $right } 'le' { $left -le $right } default { $false }
                }
            }
            return [pscustomobject]@{ Status = $(if ($pass) { 'Met' } else { 'Gap' }); Metric = $value; Rule = $null; Evidence = $null }
        }
        { $_ -in 'allOf', 'anyOf' } {
            $parts = @(
                foreach ($s in @(Get-MaturityPropertyValue $Source 'sources' @())) {
                    Resolve-MaturitySource -Source $s -Metrics $Metrics -OutcomeById $OutcomeById -EvidenceById $EvidenceById
                }
            )
            $statuses = @($parts | ForEach-Object { $_.Status })
            $status = if ($kind -eq 'allOf') {
                if ($statuses -contains 'Gap') { 'Gap' } elseif ($statuses -contains 'Unknown') { 'Unknown' } else { 'Met' }
            } else {
                if ($statuses -contains 'Met') { 'Met' } elseif ($statuses -contains 'Unknown') { 'Unknown' } else { 'Gap' }
            }
            $decider = @($parts | Where-Object Status -eq $status | Select-Object -First 1)
            $metric = @($parts | Where-Object { $null -ne $_.Metric } | Select-Object -First 1 | ForEach-Object { $_.Metric })
            $evidence = @($parts | Where-Object { $_.Status -eq $status -and $_.Evidence } | ForEach-Object { $_.Evidence }) -join ' '
            return [pscustomobject]@{
                Status   = $status
                Metric   = $(if ($metric.Count -gt 0) { $metric[0] } else { $null })
                Rule     = $(if ($decider.Count -gt 0) { $decider[0].Rule } else { $null })
                Evidence = $(if ($evidence) { $evidence } else { $null })
            }
        }
        default { throw "Unknown maturity source kind '$kind'." }
    }
}

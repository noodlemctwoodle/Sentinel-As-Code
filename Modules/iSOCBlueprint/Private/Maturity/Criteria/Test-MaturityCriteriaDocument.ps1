#Requires -Version 7.6

<#
.SYNOPSIS
    Check maturity-criteria.json against the metric names and its own rules.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Maturity/Criteria/Test-MaturityCriteriaDocument.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Maturity Engine
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Test-MaturityCriteriaDocument {
    <#
    .SYNOPSIS
        Throw when the criteria document is malformed: duplicate or
        misnamed ids, unknown areas, metrics, CSF ids, levels or sources.

    .PARAMETER Document
        The parsed criteria document.

    .PARAMETER MetricNames
        The metric names New-MaturityMetric produces.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'MetricNames', Justification = 'Read inside the $checkSource script block, which the analyser does not follow.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] $Document,
        [Parameter(Mandatory = $true)] [string[]] $MetricNames
    )
    $problems = [System.Collections.Generic.List[string]]::new()
    $areaIds = @(Get-MaturityPropertyValue $Document 'areas' @() | ForEach-Object { [string](Get-MaturityPropertyValue $_ 'id' '') })
    if ($areaIds.Count -eq 0) { $problems.Add('no areas defined') }
    if (@($areaIds | Sort-Object -Unique).Count -ne $areaIds.Count) { $problems.Add('duplicate area ids') }
    $levels = @(Get-MaturityPropertyValue $Document 'levels' @() | ForEach-Object { [int](Get-MaturityPropertyValue $_ 'level' -1) } | Sort-Object)
    if (($levels -join ',') -ne '0,1,2,3,4,5') { $problems.Add("levels must be exactly 0 to 5 (found $($levels -join ','))") }
    $csfIds = @((Get-MaturityPropertyValue $Document 'csf.subcategories' @{}).PSObject.Properties.Name)
    $csfFunctions = @((Get-MaturityPropertyValue $Document 'csf.functions' @{}).PSObject.Properties.Name)
    foreach ($id in $csfIds) {
        if ($id -notmatch '^([A-Z]{2})\.[A-Z]{2}-\d{2}$' -or $Matches[1] -notin $csfFunctions) { $problems.Add("CSF id '$id' does not belong to a listed function") }
    }

    $seen = [System.Collections.Generic.HashSet[string]]::new()
    $criteria = @(Get-MaturityPropertyValue $Document 'criteria' @())
    if ($criteria.Count -eq 0) { $problems.Add('no criteria defined') }
    $checkSource = {
        param($Source, $Id)
        $kind = [string](Get-MaturityPropertyValue $Source 'kind' '')
        switch ($kind) {
            'gapRule' {
                if (([string](Get-MaturityPropertyValue $Source 'rule' '')) -notmatch '^SAC-[A-Z]{2,4}-\d{2}$') { $problems.Add("$Id gapRule source needs a SAC finding id") }
            }
            'metric' {
                $path = [string](Get-MaturityPropertyValue $Source 'path' '')
                if ($path -notin $MetricNames) { $problems.Add("$Id references unknown metric '$path'") }
                if (([string](Get-MaturityPropertyValue $Source 'op' '')) -notin @('gt', 'ge', 'eq', 'lt', 'le')) { $problems.Add("$Id metric source has an unknown op") }
                if ($null -eq (Get-MaturityPropertyValue $Source 'value' $null)) { $problems.Add("$Id metric source has no value") }
            }
            { $_ -in 'allOf', 'anyOf' } {
                $inner = @(Get-MaturityPropertyValue $Source 'sources' @())
                if ($inner.Count -lt 2) { $problems.Add("$Id $kind needs at least two sources") }
                foreach ($s in $inner) { & $checkSource $s $Id }
            }
            default { $problems.Add("$Id has an unknown source kind '$kind'") }
        }
    }
    foreach ($c in $criteria) {
        $id = [string](Get-MaturityPropertyValue $c 'id' '')
        if ($id -notmatch '^SAC-[A-Z]+-\d{2}$') { $problems.Add("criterion id '$id' does not match SAC-<AREA>-NN") }
        if (-not $seen.Add($id)) { $problems.Add("duplicate criterion id '$id'") }
        $area = [string](Get-MaturityPropertyValue $c 'area' '')
        if ($area -notin $areaIds) { $problems.Add("$id names unknown area '$area'") }
        if ($id -notlike "SAC-$area-*") { $problems.Add("$id does not carry its area '$area' in the id") }
        if (([string](Get-MaturityPropertyValue $c 'kind' '')) -notin @('practice', 'coverage')) { $problems.Add("$id kind must be practice or coverage") }
        if ([string]::IsNullOrWhiteSpace([string](Get-MaturityPropertyValue $c 'name' ''))) { $problems.Add("$id has no name") }
        if ((ConvertTo-MaturityNumber (Get-MaturityPropertyValue $c 'weight' 0)) -le 0) { $problems.Add("$id weight must be positive") }
        if (([string](Get-MaturityPropertyValue $c 'effort' '')) -notin @('Low', 'Medium', 'High')) { $problems.Add("$id effort must be Low, Medium or High") }
        foreach ($ref in @(Get-MaturityPropertyValue $c 'csf' @())) {
            if ([string]$ref -notin $csfIds) { $problems.Add("$id references CSF subcategory '$ref' that is not in the reference") }
        }
        $source = Get-MaturityPropertyValue $c 'source' $null
        if ($null -eq $source) { $problems.Add("$id has no source") } else { & $checkSource $source $id }
        foreach ($text in @((Get-MaturityPropertyValue $c 'name' ''), (Get-MaturityPropertyValue $c 'impact' ''), (Get-MaturityPropertyValue $c 'guidance' ''))) {
            if ([string]$text -match [char]0x2014) { $problems.Add("$id text contains an em-dash") }
        }
        foreach ($text in @((Get-MaturityPropertyValue $c 'evidence.met' ''), (Get-MaturityPropertyValue $c 'evidence.gap' ''))) {
            if ([string]$text -match '\((s|es|ies)\)') { $problems.Add("$id evidence writes a plural as (s); use {singular|plural}") }
        }
    }
    if ($problems.Count -gt 0) {
        throw "maturity-criteria.json is invalid: $($problems -join '; ')"
    }
}

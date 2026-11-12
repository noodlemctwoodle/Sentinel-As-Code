#Requires -Version 7.6

<#
.SYNOPSIS
    Fill a criterion's evidence template from its metric.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Maturity/Helpers/Format-MaturityEvidence.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, Maturity Engine
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function Format-MaturityEvidence {
    <#
    .SYNOPSIS
        Fill the {metric}, {metric:gb} and {metric:1dp} tokens and the
        {singular|plural} choices in an evidence template.

    .DESCRIPTION
        {metric} reads as a count (1,512) and a fraction to one place
        (95.5); {metric:gb} as GB to two places (176,702.70); {metric:1dp}
        to one place whatever the value (240.0). {rule|rules} picks the
        singular when the metric is one and the plural otherwise.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)] [AllowNull()] [AllowEmptyString()] [string] $Template,
        [Parameter(Mandatory = $false)] [AllowNull()] $Metric
    )
    if ([string]::IsNullOrWhiteSpace($Template)) { return $null }
    $isNumber = ($null -ne $Metric) -and ($Metric -isnot [bool])
    $n = if ($isNumber) { ConvertTo-MaturityNumber $Metric } else { 0.0 }
    $text = [regex]::Replace($Template, '\{metric(?::(gb|1dp))?\}', {
        param($m)
        if ($null -eq $Metric) { return 'unknown' }
        if ($Metric -is [bool]) { return $(if ($Metric) { 'yes' } else { 'no' }) }
        switch ($m.Groups[1].Value) {
            'gb'    { Format-BlueprintGb $n }
            '1dp'   { Format-BlueprintNumber $n -Decimals 1 }
            default { if ($n -eq [math]::Floor($n)) { Format-BlueprintCount $n } else { Format-BlueprintNumber $n -Decimals 1 } }
        }
    })
    return [regex]::Replace($text, '\{([^{}|]+)\|([^{}|]+)\}', { param($m) if ($isNumber -and $n -eq 1) { $m.Groups[1].Value } else { $m.Groups[2].Value } })
}

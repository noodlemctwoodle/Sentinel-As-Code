#Requires -Version 7.6

<#
.SYNOPSIS
    A script block that loads some of the module's private functions into the
    scope that dot-sources it, for tests that run without the module.

.DESCRIPTION
    The module loads every file under Modules/iSOCBlueprint/Private when it is
    imported. A test that exercises one area on its own dot-sources the
    block this returns:

        . (Get-iSOCBlueprintAreaLoader -Bundle Gap)

    Dot-sourcing the block (not calling it) defines the functions in the
    caller's scope, as dot-sourcing the files would.

.NOTES
    File:         Tests/iSOCBlueprint/_helpers/Get-iSOCBlueprintAreaLoader.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.1.0
    Last Updated: 2026-11-16
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function Get-iSOCBlueprintAreaLoader {
    <#
    .SYNOPSIS
        A script block that dot-sources every file of the named private
        areas, in path order.

    .PARAMETER Area
        Folders under Modules/iSOCBlueprint/Private to load, in order.

    .PARAMETER Bundle
        A named set of areas, as the engine loaders it replaces loaded them:
        Gap (the check functions, Get-SentinelGap and what they read),
        Maturity, Cost, WhatsNew or CaptureSummary.

    .PARAMETER Strict
        Turn strict mode on (latest) in the caller's scope first, as
        dot-sourcing the old GapChecks loader did for a test that read the
        checks directly.

    .OUTPUTS
        [scriptblock]
    #>
    [CmdletBinding(DefaultParameterSetName = 'Area')]
    [OutputType([scriptblock])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Area')] [string[]] $Area,
        [Parameter(Mandatory, ParameterSetName = 'Bundle')] [ValidateSet('Gap', 'Maturity', 'Cost', 'WhatsNew', 'CaptureSummary')] [string] $Bundle,
        [switch] $Strict
    )

    $bundles = @{
        Gap            = @{ Area = 'Lookup', 'Format', 'Gap', 'GapAnalysis'; Strict = $false }
        Maturity       = @{ Area = 'Lookup', 'Format', 'Maturity'; Strict = $false }
        Cost           = @{ Area = 'Cost'; Strict = $false }
        WhatsNew       = @{ Area = 'WhatsNew'; Strict = $false }
        CaptureSummary = @{ Area = 'CaptureSummary'; Strict = $false }
    }
    if ($PSCmdlet.ParameterSetName -eq 'Bundle') {
        $Area = $bundles[$Bundle].Area
        $Strict = [switch]($Strict -or $bundles[$Bundle].Strict)
    }

    $privateRoot = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) 'Modules/iSOCBlueprint/Private'
    $lines = [System.Collections.Generic.List[string]]::new()
    if ($Strict) { $lines.Add('Set-StrictMode -Version Latest') }
    foreach ($a in $Area) {
        foreach ($file in Get-ChildItem -LiteralPath (Join-Path $privateRoot $a) -Filter '*.ps1' -File -Recurse | Sort-Object FullName) {
            $lines.Add(". '$($file.FullName.Replace("'", "''"))'")
        }
    }
    [scriptblock]::Create($lines -join "`n")
}

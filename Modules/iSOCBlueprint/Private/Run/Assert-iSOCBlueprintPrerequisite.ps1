#Requires -Version 7.6

<#
.SYNOPSIS
    Stop with the list of what is missing when the machine lacks a module or
    tool a step needs.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Run/Assert-iSOCBlueprintPrerequisite.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.1.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, prerequisites
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Assert-iSOCBlueprintPrerequisite {
    <#
    .SYNOPSIS
        Throw when a required module or tool for the given steps is missing.

    .DESCRIPTION
        The engine scripts carried a #Requires -Modules line that stopped
        them before they did anything. A function has no such line, so a
        step that needs a module checks for it here, against the same list
        Test-iSOCBlueprintPrerequisite reports.

    .PARAMETER Step
        The steps whose requirements are checked: Collect, Render,
        ChartImage, Word, Site or Publish.

    .PARAMETER For
        What the message calls the thing that needs them: "This <For>
        needs:". Defaults to 'command'.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Collect', 'Render', 'ChartImage', 'Word', 'Site', 'Publish')]
        [string[]] $Step,

        [string] $For = 'command'
    )

    $missing = @(Test-iSOCBlueprintPrerequisite -Step $Step | Where-Object { $_.Required -and -not $_.Found })
    if ($missing.Count -gt 0) {
        $lines = $missing | ForEach-Object { "  - $($_.Name) ($($_.Step -join ', ')): $($_.Detail)" }
        throw "This $For needs:`n$($lines -join "`n")"
    }
}

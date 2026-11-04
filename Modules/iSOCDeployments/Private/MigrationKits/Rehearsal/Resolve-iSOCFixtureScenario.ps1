#Requires -Version 7.2

<#
.SYNOPSIS
    The dependency fixture scenarios to use, in create order.

.DESCRIPTION
    None asked for is all of them; Hunt brings OneHop, whose parser its query
    reads.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/Rehearsal/Resolve-iSOCFixtureScenario.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.0
    Last Updated: 2026-11-04
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Resolve-iSOCFixtureScenario {
    <#
    .SYNOPSIS
        The dependency fixture scenarios to use, in create order.

    .DESCRIPTION
        An empty selection is every scenario. Hunt brings OneHop with it: the
        hunting query reaches its table through the OneHop parser and would
        otherwise name an alias that does not exist. Names are matched
        without case and returned in the create order (Direct, OneHop,
        TwoHop, Cycle, Orphan, Hunt).

    .PARAMETER Scenario
        The scenarios asked for.

    .OUTPUTS
        [string[]]

    .EXAMPLE
        Resolve-iSOCFixtureScenario -Scenario Hunt
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [AllowEmptyCollection()]
        [AllowNull()]
        [string[]] $Scenario
    )

    $order = (Get-iSOCDependencyFixtureSetting).ScenarioOrder
    if (-not $Scenario -or $Scenario.Count -eq 0) { return $order }

    $selected = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($name in $Scenario) {
        if (-not [string]::IsNullOrWhiteSpace($name)) { [void]$selected.Add($name.Trim()) }
    }
    if ($selected.Contains('Hunt')) { [void]$selected.Add('OneHop') }
    @($order | Where-Object { $selected.Contains($_) })
}

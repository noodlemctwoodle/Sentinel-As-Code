#Requires -Version 7.2

<#
.SYNOPSIS
    Say where two ARM templates differ in what they deploy, if they do.

.NOTES
    File:         Modules/iSOCDeployments/Private/Bicep/Compare-iSOCArmTemplate.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-06
    Version:      0.2.0
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Compare-iSOCArmTemplate {
    <#
    .SYNOPSIS
        Return the first difference between two templates, or nothing when
        they deploy the same thing.

    .DESCRIPTION
        Both templates are reduced with Resolve-iSOCArmTemplate and walked
        together. The first path where they differ is returned with both
        values, for example
        "resources[0].properties.state: 'Enabled' in the first, 'Disabled' in the second".

    .PARAMETER Expected
        The first template (the JSON playbook).

    .PARAMETER Actual
        The second template (the compiled Bicep).

    .PARAMETER InlineParameter
        Parameters both templates read as their default, passed to
        Resolve-iSOCArmTemplate: location, when the Bicep writer added it.

    .OUTPUTS
        [string] The difference; nothing when there is none.

    .EXAMPLE
        Compare-iSOCArmTemplate -Expected $json -Actual $compiled
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [object] $Expected,

        [Parameter(Mandatory)]
        [object] $Actual,

        [string[]] $InlineParameter = @()
    )

    $show = {
        param($Value)
        if ($null -eq $Value) { return 'nothing' }
        $json = ConvertTo-Json -InputObject $Value -Depth 100 -Compress
        if ($json.Length -gt 120) { $json = $json.Substring(0, 117) + '...' }
        $json
    }
    $walk = $null
    $walk = {
        param([string] $Path, $Left, $Right)
        $leftIsMap = $Left -is [System.Collections.IDictionary]
        $rightIsMap = $Right -is [System.Collections.IDictionary]
        if ($leftIsMap -and $rightIsMap) {
            $keys = @(@($Left.Keys) + @($Right.Keys) | Sort-Object -Unique -CaseSensitive)
            foreach ($key in $keys) {
                $child = if ($Path) { "$Path.$key" } else { [string]$key }
                if (-not $Left.Contains($key)) { return "${child}: missing in the first, $(& $show $Right[$key]) in the second" }
                if (-not $Right.Contains($key)) { return "${child}: $(& $show $Left[$key]) in the first, missing in the second" }
                $found = & $walk $child $Left[$key] $Right[$key]
                if ($found) { return $found }
            }
            return $null
        }
        $leftIsList = $Left -is [array]
        $rightIsList = $Right -is [array]
        if ($leftIsList -and $rightIsList) {
            if ($Left.Count -ne $Right.Count) { return "${Path}: $($Left.Count) items in the first, $($Right.Count) in the second" }
            for ($i = 0; $i -lt $Left.Count; $i++) {
                $found = & $walk "$Path[$i]" $Left[$i] $Right[$i]
                if ($found) { return $found }
            }
            return $null
        }
        if ($leftIsMap -or $rightIsMap -or $leftIsList -or $rightIsList -or "$($Left)" -cne "$($Right)" -or
            ($null -eq $Left) -ne ($null -eq $Right) -or ($Left -is [bool]) -ne ($Right -is [bool]) -or ($Left -is [string]) -ne ($Right -is [string])) {
            return "${Path}: $(& $show $Left) in the first, $(& $show $Right) in the second"
        }
        $null
    }

    & $walk '' (Resolve-iSOCArmTemplate -Template $Expected -InlineParameter $InlineParameter) (Resolve-iSOCArmTemplate -Template $Actual -InlineParameter $InlineParameter)
}

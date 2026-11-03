#Requires -Version 7.2

<#
.SYNOPSIS
    One changed field of a drift report, in Markdown.

.DESCRIPTION
    Copied from Format-FieldBlock (Tools/Test-SentinelRuleDrift.ps1).

.NOTES
    File:         Modules/iSOCDeployments/Private/Drift/Format-iSOCDriftFieldBlock.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.0
    Last Updated: 2026-11-03
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Format-iSOCDriftFieldBlock {
    <#
    .SYNOPSIS
        Return a heading for the field, then both values.

    .DESCRIPTION
        Short values go inline, each in code quotes ((unset) when there is
        none). A value with a line break or over 120 characters gets a diff
        of the two, then both in full, so nothing is cut.

    .PARAMETER Modification
        A report modification: field, deployed and expected.

    .PARAMETER DeployedLabel
        What to call the workspace's value.

    .PARAMETER ExpectedLabel
        What to call the repository's or template's value.

    .OUTPUTS
        [string]

    .EXAMPLE
        Format-iSOCDriftFieldBlock -Modification $m -DeployedLabel 'Deployed' -ExpectedLabel 'Template'
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [object] $Modification,

        [Parameter(Mandatory)]
        [string] $DeployedLabel,

        [Parameter(Mandatory)]
        [string] $ExpectedLabel
    )

    $sb = [System.Text.StringBuilder]::new()
    $field = $Modification.field
    $dep = $Modification.deployed
    $exp = $Modification.expected

    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("##### ``$field``")
    [void]$sb.AppendLine('')

    if (-not (Test-iSOCMultiLineValue $dep) -and -not (Test-iSOCMultiLineValue $exp)) {
        $depRendered = if ($null -eq $dep) { '*(unset)*' } else { '`' + $dep + '`' }
        $expRendered = if ($null -eq $exp) { '*(unset)*' } else { '`' + $exp + '`' }
        [void]$sb.AppendLine("- ${DeployedLabel}: $depRendered")
        [void]$sb.AppendLine("- ${ExpectedLabel}: $expRendered")
        return $sb.ToString()
    }

    [void]$sb.AppendLine("Diff (lines starting ``-`` are ${ExpectedLabel}, ``+`` are ${DeployedLabel}):")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('```diff')
    [void]$sb.AppendLine((Get-iSOCLineDiff -Before ([string]$exp) -After ([string]$dep)))
    [void]$sb.AppendLine('```')
    foreach ($side in @(@{ Label = $DeployedLabel; Value = $dep }, @{ Label = $ExpectedLabel; Value = $exp })) {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine("**$($side.Label) (full):**")
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('```kql')
        [void]$sb.AppendLine([string]$side.Value)
        [void]$sb.AppendLine('```')
    }
    $sb.ToString()
}

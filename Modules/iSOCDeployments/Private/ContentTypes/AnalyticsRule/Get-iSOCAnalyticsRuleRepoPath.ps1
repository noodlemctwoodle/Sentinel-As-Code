#Requires -Version 7.6

<#
.SYNOPSIS
    GetRepoPath handler for analytics rules: where an absorbed rule's file
    goes.

.DESCRIPTION
    Copied from the path layout in Save-AbsorbedRule
    (Tools/Test-SentinelRuleDrift.ps1).

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/AnalyticsRule/Get-iSOCAnalyticsRuleRepoPath.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCAnalyticsRuleRepoPath {
    <#
    .SYNOPSIS
        Return the repository-relative path for a rule absorbed from the
        workspace.

    .DESCRIPTION
        A Content Hub rule goes to
        Content/AnalyticalRules/AbsorbedFromPortal/ContentHub/<solution>/,
        the solution slugged to 60 characters (Unattributed when it is not
        known); an orphan to Content/AnalyticalRules/AbsorbedFromPortal/Orphans/.
        The file is named after the rule's display name (its name when it has
        none), slugged to 80 characters.

    .PARAMETER WorkspaceItem
        A rule as Read-iSOCAnalyticsRuleWorkspace returns it.

    .PARAMETER Provenance
        ContentHub or Orphan.

    .PARAMETER SolutionName
        The Content Hub solution.

    .OUTPUTS
        [string] A forward-slash path under the repository root.

    .EXAMPLE
        Get-iSOCAnalyticsRuleRepoPath -WorkspaceItem $rule -Provenance ContentHub -SolutionName 'Azure Activity'
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [psobject] $WorkspaceItem,

        [Parameter(Mandatory)]
        [ValidateSet('ContentHub', 'Orphan')]
        [string] $Provenance,

        [string] $SolutionName
    )

    $base = 'Content/AnalyticalRules/AbsorbedFromPortal'
    $folder = if ($Provenance -eq 'ContentHub') {
        $solutionSlug = if ($SolutionName) { ConvertTo-iSOCFileSlug -Value $SolutionName -MaxLength 60 } else { 'Unattributed' }
        "$base/ContentHub/$solutionSlug"
    }
    else {
        "$base/Orphans"
    }

    $displayName = [string](Get-iSOCPropertyValue -InputObject $WorkspaceItem -Path 'properties.displayName')
    if ([string]::IsNullOrWhiteSpace($displayName)) { $displayName = [string]$WorkspaceItem.name }
    "$folder/$(ConvertTo-iSOCFileSlug -Value $displayName -MaxLength 80).yaml"
}

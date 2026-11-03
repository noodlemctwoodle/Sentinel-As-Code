#Requires -Version 7.2

<#
.SYNOPSIS
    The template file name for a Logic App.

.DESCRIPTION
    Copied from Get-PlaybookFileName (847ef86:Tools/Export-Playbooks.ps1).

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/Playbook/Get-iSOCPlaybookFileName.ps1
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

function Get-iSOCPlaybookFileName {
    <#
    .SYNOPSIS
        Return a Logic App's name without a leading category prefix.

    .DESCRIPTION
        Module-AddSentinelComment becomes AddSentinelComment, matching the
        templates under Content/Playbooks/, whose PlaybookName default
        keeps the full name. The prefix is matched in any case, and a name
        that is only the prefix is kept.

    .PARAMETER LogicAppName
        The Logic App's name.

    .OUTPUTS
        [string] The file name without its extension.

    .EXAMPLE
        Get-iSOCPlaybookFileName -LogicAppName 'Module-AddSentinelComment'
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $LogicAppName
    )

    foreach ($prefix in @('Incident', 'Entity', 'Alert', 'Module', 'Watchlist', 'Other')) {
        $withDash = "$prefix-"
        if ($LogicAppName.Length -gt $withDash.Length -and $LogicAppName.StartsWith($withDash, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $LogicAppName.Substring($withDash.Length)
        }
    }
    $LogicAppName
}

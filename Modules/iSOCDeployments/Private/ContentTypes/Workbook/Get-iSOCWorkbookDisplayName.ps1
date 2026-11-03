#Requires -Version 7.2

<#
.SYNOPSIS
    A workbook's display name without the workspace suffix Microsoft adds.

.DESCRIPTION
    Copied from Remove-WorkspaceSuffix (Tools/Export-SentinelWorkbooks.ps1).

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/Workbook/Get-iSOCWorkbookDisplayName.ps1
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

function Get-iSOCWorkbookDisplayName {
    <#
    .SYNOPSIS
        Return a display name without a trailing ' - <workspace name>'.

    .DESCRIPTION
        Microsoft-published templates instantiated in a workspace carry the
        workspace's name at the end of their display name ('Data Collection
        Rule Toolkit - law-sentinel'). The name is matched literally and
        case-sensitively, only at the very end; a display name without it
        is returned as it is.

    .PARAMETER DisplayName
        The workbook's display name.

    .PARAMETER WorkspaceName
        The workspace's name.

    .OUTPUTS
        [string] The display name.

    .EXAMPLE
        Get-iSOCWorkbookDisplayName -DisplayName 'Data Collection Rule Toolkit - law-sentinel' -WorkspaceName 'law-sentinel'
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $DisplayName,

        [Parameter(Mandatory)]
        [string] $WorkspaceName
    )

    $pattern = ' - ' + [regex]::Escape($WorkspaceName) + '$'
    [regex]::Replace($DisplayName, $pattern, '')
}

#Requires -Version 7.6

<#
.SYNOPSIS
    Whether writing an item would create, update or leave its files.

.DESCRIPTION
    Lets Export-iSOCContent say under -WhatIf what it would do, and leave
    alone an item whose files would not change.

.NOTES
    File:         Modules/iSOCDeployments/Private/Export/Get-iSOCRepoItemChange.ps1
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

function Get-iSOCRepoItemChange {
    <#
    .SYNOPSIS
        Return Created, Updated or Unchanged for an item's new content
        against what its files hold.

    .DESCRIPTION
        Created when there is no file or folder; Unchanged when every file
        the content names holds that text already, case included; Updated
        otherwise. Files of a folder that the content does not name are not
        compared, because saving leaves them alone.

    .PARAMETER Existing
        What the files hold, from Read-iSOCRepoItemFile.

    .PARAMETER Content
        What a ToRepoFile handler returned: the file's text, or the
        folder's files by name.

    .OUTPUTS
        [string] Created, Updated or Unchanged.

    .EXAMPLE
        $change = Get-iSOCRepoItemChange -Existing $existing -Content $content
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [object] $Existing,

        [Parameter(Mandatory)]
        [object] $Content
    )

    if ($null -eq $Existing) { return 'Created' }
    if ($Content -is [System.Collections.IDictionary]) {
        foreach ($name in $Content.Keys) {
            if (-not $Existing.Contains($name)) { return 'Updated' }
            if ([string]$Existing[$name] -cne [string]$Content[$name]) { return 'Updated' }
        }
        return 'Unchanged'
    }
    if ([string]$Existing -ceq [string]$Content) { 'Unchanged' } else { 'Updated' }
}

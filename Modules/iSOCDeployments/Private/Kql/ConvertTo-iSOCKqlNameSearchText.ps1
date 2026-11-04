#Requires -Version 7.2

<#
.SYNOPSIS
    Blank out the name positions that never resolve to a function in the workspace.

.DESCRIPTION
    Runs on Get-iSOCKqlCodeText's output: cross-cluster references, member
    access and assignment targets are removed.

.NOTES
    File:         Modules/iSOCDeployments/Private/Kql/ConvertTo-iSOCKqlNameSearchText.ps1
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

function ConvertTo-iSOCKqlNameSearchText {
    <#
    .SYNOPSIS
        Blank out the name positions that never resolve to a function in the
        workspace.

    .DESCRIPTION
        Runs on the output of Get-iSOCKqlCodeText, so comments and strings
        are already gone. Removed:

          cluster(...).X, database(...).X, workspace(...).X, app(...).X
              a reference into another cluster, database, workspace or app,
              never a local function
          Something.Name
              member access; a workspace function is never dotted
          Name =
              an assignment target, a new column or variable; == and =~ are
              not assignments

    .PARAMETER Text
        The code text.

    .OUTPUTS
        [string] The text with those positions blank, or '' for no text.

    .EXAMPLE
        ConvertTo-iSOCKqlNameSearchText -Text 'workspace("x").T | extend A = B.C'
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Text
    )

    if ([string]::IsNullOrEmpty($Text)) { return '' }

    $qualifier = '(?:cluster|database|workspace|app)\s*\([^()]*\)\s*\.\s*'
    $out = [regex]::Replace($Text, "(?<![A-Za-z0-9_])(?:$qualifier)+[A-Za-z_][A-Za-z0-9_]*", ' ')
    $out = [regex]::Replace($out, '\.\s*[A-Za-z_][A-Za-z0-9_]*', ' ')
    [regex]::Replace($out, '(?<![A-Za-z0-9_])[A-Za-z_][A-Za-z0-9_]*(\s*=(?![=~]))', ' $1')
}

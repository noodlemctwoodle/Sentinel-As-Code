#Requires -Version 7.2

<#
.SYNOPSIS
    Write a parsed ARM expression back as canonical text.

.DESCRIPTION
    Two expressions that mean the same thing written with different spacing
    or function-name case give the same text, so the Bicep writer can tell
    that resourceId('Microsoft.Web/connections', variables('X')) names the
    resource whose name is [variables('X')].

.NOTES
    File:         Modules/iSOCDeployments/Private/Bicep/ConvertTo-iSOCArmExpressionText.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-06
    Version:      0.1.0
    Last Updated: 2026-11-06
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function ConvertTo-iSOCArmExpressionText {
    <#
    .SYNOPSIS
        Return a node from ConvertFrom-iSOCArmExpression as canonical text.

    .DESCRIPTION
        Function and member names in lower case, no spaces, strings in
        single quotes with quotes doubled. The text is for comparing, not
        for writing into a template.

    .PARAMETER Node
        The node.

    .OUTPUTS
        [string] The canonical text.

    .EXAMPLE
        ConvertTo-iSOCArmExpressionText -Node (ConvertFrom-iSOCArmExpression "variables( 'X' )")
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Node
    )

    switch ($Node.Kind) {
        'String' { "'" + $Node.Value.Replace("'", "''") + "'" }
        'Number' { [string]$Node.Value }
        'Call' { $Node.Name.ToLowerInvariant() + '(' + ((@($Node.Arguments) | ForEach-Object { ConvertTo-iSOCArmExpressionText -Node $_ }) -join ',') + ')' }
        'Member' { (ConvertTo-iSOCArmExpressionText -Node $Node.Target) + '.' + $Node.Name.ToLowerInvariant() }
        'Index' { (ConvertTo-iSOCArmExpressionText -Node $Node.Target) + '[' + (ConvertTo-iSOCArmExpressionText -Node $Node.Index) + ']' }
        default { throw "Unknown ARM expression node '$($Node.Kind)'." }
    }
}

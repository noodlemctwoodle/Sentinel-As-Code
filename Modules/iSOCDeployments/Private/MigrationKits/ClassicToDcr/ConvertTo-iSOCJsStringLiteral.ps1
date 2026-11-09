#Requires -Version 7.6

<#
.SYNOPSIS
    Escape text for a double-quoted JavaScript string inside a script element.

.DESCRIPTION
    ConvertTo-Json escapes the quote, backslash and control characters; then
    < and > (so </script> cannot close the element) and U+2028 and U+2029 are
    escaped too.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/ClassicToDcr/ConvertTo-iSOCJsStringLiteral.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function ConvertTo-iSOCJsStringLiteral {
    <#
    .SYNOPSIS
        Escape text for a double-quoted JavaScript string inside a script
        element.

    .DESCRIPTION
        ConvertTo-Json on a string escapes the backslash, the double quote
        and the control characters and wraps the result in quotes, which are
        trimmed. Then < and > are written < and >, so </script>
        cannot close the element early, and U+2028 and U+2029, which end a
        JavaScript line, are escaped. System.Web is not used: it is not
        loaded on PowerShell 7.

    .PARAMETER Value
        The text.

    .OUTPUTS
        [string] The literal's body, without quotes.

    .EXAMPLE
        $template.Replace('{{DATA_JSON}}', (ConvertTo-iSOCJsStringLiteral -Value $json))
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Value
    )

    $quoted = $Value | ConvertTo-Json
    $literal = $quoted.Substring(1, $quoted.Length - 2)

    $u = [char]0x5C
    $literal = $literal.Replace('<', "${u}u003c").Replace('>', "${u}u003e")
    $literal = $literal.Replace([string][char]0x2028, "${u}u2028")
    $literal.Replace([string][char]0x2029, "${u}u2029")
}

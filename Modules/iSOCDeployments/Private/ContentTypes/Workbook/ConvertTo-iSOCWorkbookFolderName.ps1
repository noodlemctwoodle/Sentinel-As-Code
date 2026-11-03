#Requires -Version 7.2

<#
.SYNOPSIS
    The PascalCase folder name a workbook's display name makes.

.DESCRIPTION
    Copied from ConvertTo-FolderName (Tools/Export-SentinelWorkbooks.ps1).

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/Workbook/ConvertTo-iSOCWorkbookFolderName.ps1
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

function ConvertTo-iSOCWorkbookFolderName {
    <#
    .SYNOPSIS
        Return a display name as one PascalCase word.

    .DESCRIPTION
        Every run of characters other than letters and digits is a word
        break. A word with an internal lower-to-upper change (pfSense,
        ApacheTomcat) keeps its case and gains a capital first letter;
        any other word is title-cased ('GBP' becomes 'Gbp'), matching the
        folders under Content/Workbooks/. 'Microsoft Sentinel Cost (GBP) v2'
        becomes 'MicrosoftSentinelCostGbpV2'.

    .PARAMETER DisplayName
        The workbook's display name.

    .OUTPUTS
        [string] The folder name; empty when the name has no letters or
        digits.

    .EXAMPLE
        ConvertTo-iSOCWorkbookFolderName -DisplayName 'pfSense Firewall'
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $DisplayName
    )

    $words = [regex]::Split($DisplayName, '[^A-Za-z0-9]+') |
        Where-Object { $_ -ne '' } |
        ForEach-Object {
            if ($_.Length -lt 2) { $_.ToUpperInvariant() }
            elseif ($_ -cmatch '[a-z][A-Z]') { $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1) }
            else { $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1).ToLowerInvariant() }
        }
    (@($words) -join '')
}

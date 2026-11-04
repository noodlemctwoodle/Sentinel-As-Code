#Requires -Version 7.2

<#
.SYNOPSIS
    A stable id made from a name.

.DESCRIPTION
    Copied from New-CommunityRuleId (Tools/Import-CommunityRules.ps1).

.NOTES
    File:         Modules/iSOCDeployments/Private/Community/New-iSOCCommunityRuleId.ps1
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

function New-iSOCCommunityRuleId {
    <#
    .SYNOPSIS
        Return the RFC 4122 version 5 (SHA-1) GUID of a name in the URL
        namespace, so the same name gives the same id on every run.

    .PARAMETER Name
        The name: the source repository and the rule's path.

    .OUTPUTS
        [string] The GUID, in lower case.

    .EXAMPLE
        New-iSOCCommunityRuleId -Name 'https://github.com/example-org/rules#SigninLogs/x.yaml'
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Computes a GUID from a name; nothing changes.')]
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Name
    )

    $namespace = [byte[]](0x6b, 0xa7, 0xb8, 0x11, 0x9d, 0xad, 0x11, 0xd1, 0x80, 0xb4, 0x00, 0xc0, 0x4f, 0xd4, 0x30, 0xc8)
    $data = [byte[]]($namespace + [System.Text.Encoding]::UTF8.GetBytes($Name))
    $sha1 = [System.Security.Cryptography.SHA1]::Create()
    try { $hash = $sha1.ComputeHash($data) }
    finally { $sha1.Dispose() }
    $hash[6] = ($hash[6] -band 0x0f) -bor 0x50
    $hash[8] = ($hash[8] -band 0x3f) -bor 0x80
    $hex = -join ($hash[0..15] | ForEach-Object { $_.ToString('x2') })
    '{0}-{1}-{2}-{3}-{4}' -f $hex.Substring(0, 8), $hex.Substring(8, 4), $hex.Substring(12, 4), $hex.Substring(16, 4), $hex.Substring(20, 12)
}

#Requires -Version 7.6

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
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

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

    ConvertTo-iSOCNameBasedGuid -Name $Name
}

#Requires -Version 7.2

<#
.SYNOPSIS
    The outcome of importing one community rule.

.DESCRIPTION
    One per rule the source holds, whatever happened to it.

.NOTES
    File:         Modules/iSOCDeployments/Private/Community/New-iSOCCommunityResult.ps1
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

function New-iSOCCommunityResult {
    <#
    .SYNOPSIS
        Build a community import result.

    .PARAMETER Category
        The category.

    .PARAMETER Name
        The rule's name, or its file name when it was left out.

    .PARAMETER Path
        The rule file, relative to the output folder.

    .PARAMETER Outcome
        Created, Updated, Unchanged, Skipped or WhatIf.

    .PARAMETER Reason
        Why, when the outcome is not a plain one.

    .PARAMETER Id
        The id written.

    .PARAMETER UpstreamId
        The id the source gave, when it is not the one written.

    .OUTPUTS
        [pscustomobject] iSOCDeployments.CommunityRuleResult.

    .EXAMPLE
        New-iSOCCommunityResult -Category SigninLogs -Name 'Spray' -Path 'SigninLogs/spray.yaml' -Outcome Created
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds an object in memory; nothing outside the call changes.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $Category,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Name,

        [AllowEmptyString()]
        [string] $Path = '',

        [Parameter(Mandatory)]
        [ValidateSet('Created', 'Updated', 'Unchanged', 'Skipped', 'WhatIf')]
        [string] $Outcome,

        [AllowEmptyString()]
        [string] $Reason = '',

        [AllowEmptyString()]
        [string] $Id = '',

        [AllowEmptyString()]
        [string] $UpstreamId = ''
    )

    [pscustomobject]@{
        PSTypeName = 'iSOCDeployments.CommunityRuleResult'
        Category   = $Category
        Name       = $Name
        Path       = $Path
        Outcome    = $Outcome
        Reason     = $Reason
        Id         = $Id
        UpstreamId = $UpstreamId
    }
}

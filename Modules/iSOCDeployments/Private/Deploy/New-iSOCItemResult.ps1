#Requires -Version 7.6

<#
.SYNOPSIS
    The record of what happened to one content item.

.NOTES
    File:         Modules/iSOCDeployments/Private/Deploy/New-iSOCItemResult.ps1
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

function New-iSOCItemResult {
    <#
    .SYNOPSIS
        Build an item result.

    .DESCRIPTION
        Outcomes:

          Deployed          sent as the file says
          DeployedDisabled  sent disabled: a missing dependency, or a query
                            the service would not validate
          WhatIf            would have been sent; -WhatIf was given
          Unchanged         smart deployment found nothing to send
          Skipped           not sent: excluded, invalid, or a dependency is
                            missing and the type skips such items
          Failed            the file does not parse, or the service refused it

    .PARAMETER ContentType
        The content type's name.

    .PARAMETER Item
        The repository item.

    .PARAMETER Outcome
        One of the outcomes above.

    .PARAMETER Reason
        Why, in a few words; nothing for a plain Deployed.

    .PARAMETER Missing
        The dependencies that were missing, as kind:name.

    .OUTPUTS
        [pscustomobject] iSOCDeployments.ItemResult: ContentType, Name,
        Identity, RelativePath, Outcome, Reason and Missing.

    .EXAMPLE
        New-iSOCItemResult -ContentType Parser -Item $item -Outcome Deployed
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds an object in memory; nothing outside the call changes.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $ContentType,

        [Parameter(Mandatory)]
        [psobject] $Item,

        [Parameter(Mandatory)]
        [ValidateSet('Deployed', 'DeployedDisabled', 'WhatIf', 'Unchanged', 'Skipped', 'Failed')]
        [string] $Outcome,

        [string] $Reason,

        [string[]] $Missing = @()
    )

    [pscustomobject]@{
        PSTypeName   = 'iSOCDeployments.ItemResult'
        ContentType  = $ContentType
        Name         = $Item.Name
        Identity     = $Item.Identity
        RelativePath = $Item.RelativePath
        Outcome      = $Outcome
        Reason       = $Reason
        Missing      = @($Missing)
    }
}

#Requires -Version 7.2

<#
.SYNOPSIS
    What happened to one Content Hub solution or template.

.DESCRIPTION
    Replaces the counters Deploy-SentinelContentHub.ps1 kept per content
    kind (MIGRATION.md edit E19): one result per item, so a run reports
    each solution and template with the reason, not only totals.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentHub/New-iSOCContentHubResult.ps1
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

function New-iSOCContentHubResult {
    <#
    .SYNOPSIS
        Build a Content Hub item result.

    .DESCRIPTION
        Outcomes:

          Deployed    installed or created
          Updated     updated in place
          Unchanged   already current
          Protected   an analytics rule changed in the workspace, left alone
          Deprecated  a template marked [Deprecated], left out
          WhatIf      would have been sent; -WhatIf was given
          Skipped     not sent: filtered out, or nothing to send, or the
                      service refused it for a reason the workspace can fix
                      (a missing table, say)
          Failed      the request failed

    .PARAMETER ContentType
        Solution, AnalyticsRule or Workbook.

    .PARAMETER Name
        The solution's or template's display name.

    .PARAMETER Identity
        The template's contentId, or the solution's name.

    .PARAMETER Solution
        The solution the template comes from.

    .PARAMETER Outcome
        One of the outcomes above.

    .PARAMETER Reason
        Why, in a few words.

    .OUTPUTS
        [pscustomobject] iSOCDeployments.ContentHubResult: ContentType, Name,
        Identity, Solution, Outcome and Reason.

    .EXAMPLE
        New-iSOCContentHubResult -ContentType AnalyticsRule -Name $name -Identity $id -Solution 'Azure Activity' -Outcome Deployed
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds an object in memory; nothing outside the call changes.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Solution', 'AnalyticsRule', 'Workbook')]
        [string] $ContentType,

        [AllowEmptyString()]
        [AllowNull()]
        [string] $Name,

        [AllowEmptyString()]
        [AllowNull()]
        [string] $Identity,

        [AllowEmptyString()]
        [AllowNull()]
        [string] $Solution,

        [Parameter(Mandatory)]
        [ValidateSet('Deployed', 'Updated', 'Unchanged', 'Protected', 'Deprecated', 'WhatIf', 'Skipped', 'Failed')]
        [string] $Outcome,

        [string] $Reason
    )

    [pscustomobject]@{
        PSTypeName  = 'iSOCDeployments.ContentHubResult'
        ContentType = $ContentType
        Name        = $Name
        Identity    = $Identity
        Solution    = $Solution
        Outcome     = $Outcome
        Reason      = $Reason
    }
}

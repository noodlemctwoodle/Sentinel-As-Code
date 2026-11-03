#Requires -Version 7.2

<#
.SYNOPSIS
    The outcome of exporting one workspace item.

.DESCRIPTION
    One per workspace item an export looked at, whatever happened to it,
    so the run accounts for every item.

.NOTES
    File:         Modules/iSOCDeployments/Private/Export/New-iSOCExportResult.ps1
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

function New-iSOCExportResult {
    <#
    .SYNOPSIS
        Build an export result.

    .PARAMETER ContentType
        The content type's name.

    .PARAMETER Name
        The item's display name.

    .PARAMETER Identity
        The item's name in the workspace (a workbook's GUID, a Logic App's
        name).

    .PARAMETER Source
        Custom (the repository has it), ContentHub, Orphan, or nothing.

    .PARAMETER Outcome
        Created, Updated, Unchanged, Skipped, Failed or WhatIf.

    .PARAMETER Reason
        Why, when the outcome is not a plain one.

    .PARAMETER Path
        The file or folder written, or that would be, relative to the
        folder written to.

    .PARAMETER Warning
        What the item's author should know (a playbook's plain-text
        secrets).

    .OUTPUTS
        [pscustomobject] iSOCDeployments.ExportResult.

    .EXAMPLE
        New-iSOCExportResult -ContentType Workbook -Name 'Cost' -Outcome Skipped -Reason 'already in the repository'
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds an object in memory; nothing outside the call changes.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $ContentType,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Name,

        [AllowEmptyString()]
        [string] $Identity = '',

        [AllowEmptyString()]
        [string] $Source = '',

        [Parameter(Mandatory)]
        [ValidateSet('Created', 'Updated', 'Unchanged', 'Skipped', 'Failed', 'WhatIf')]
        [string] $Outcome,

        [AllowEmptyString()]
        [string] $Reason = '',

        [AllowEmptyString()]
        [string] $Path = '',

        [string[]] $Warning = @()
    )

    [pscustomobject]@{
        PSTypeName  = 'iSOCDeployments.ExportResult'
        ContentType = $ContentType
        Name        = $Name
        Identity    = $Identity
        Source      = $Source
        Outcome     = $Outcome
        Reason      = $Reason
        Path        = $Path
        Warnings    = @($Warning)
    }
}

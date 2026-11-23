#Requires -Version 7.6

<#
.SYNOPSIS
    Classify one workspace table by data lake tier

.DESCRIPTION
    One of the helpers beside Get-TableTierProfile.ps1, which describes the whole.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Lookup/Get-TableTier.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-12
    Version:      0.1.0
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-TableTier {
    <#
    .SYNOPSIS
        Classify one workspace table by data lake tier.

    .PARAMETER Table
        A workspace table resource (properties.plan, properties.retentionInDays,
        properties.totalRetentionInDays).

    .PARAMETER LakeEnrolled
        Whether the tenant is enrolled in the Sentinel data lake.

    .OUTPUTS
        [string] One of AnalyticsOnly, MirroredOnly, MirroredExtended, LakeOnly.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)] [object] $Table,
        [Parameter(Mandatory = $false)] [bool] $LakeEnrolled = $false
    )
    $props = if ($Table.PSObject.Properties['properties']) { $Table.properties } else { $null }
    $plan = if ($props -and $props.PSObject.Properties['plan']) { [string]$props.plan } else { '' }
    $r = 0; $tr = 0
    if ($props -and $props.PSObject.Properties['retentionInDays'] -and $props.retentionInDays) { $r = [int]$props.retentionInDays }
    if ($props -and $props.PSObject.Properties['totalRetentionInDays'] -and $props.totalRetentionInDays) { $tr = [int]$props.totalRetentionInDays }
    if ($plan -eq 'DataLake') { return 'LakeOnly' }
    if ($LakeEnrolled -and $tr -gt $r) { return 'MirroredExtended' }
    if ($LakeEnrolled) { return 'MirroredOnly' }
    return 'AnalyticsOnly'
}

#Requires -Version 7.6

<#
.SYNOPSIS
    Say why a workspace setting cannot be sent, if it cannot.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/WorkspaceSetting/Test-iSOCWorkspaceSetting.ps1
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

function Test-iSOCWorkspaceSetting {
    <#
    .SYNOPSIS
        Say why a workspace setting cannot be sent, if it cannot.

    .DESCRIPTION
        A setting needs a kind Sentinel has (Anomalies, EntityAnalytics,
        EyesOn or Ueba) and a name the same as its kind, which is how the
        settings API names them. Its properties, when present, are an
        object. Entity Analytics needs a list of entityProviders and UEBA a
        list of dataSources, each a list of names; which names Sentinel
        accepts is left to Sentinel, which says so when it refuses one. The
        first problem found is the one reported. A file that does not parse
        is reported as such.

    .PARAMETER Item
        A repository item from Read-iSOCWorkspaceSettingRepo.

    .OUTPUTS
        [string] The problem; nothing when the setting can be sent.

    .EXAMPLE
        $issues = @(Test-iSOCWorkspaceSetting -Item $item)
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Item
    )

    if ($Item.ParseError) { return $Item.ParseError }
    $setting = $Item.Data
    if ($setting -isnot [System.Management.Automation.PSCustomObject]) { return 'the file does not hold one setting object.' }

    $kinds = @('Anomalies', 'EntityAnalytics', 'EyesOn', 'Ueba')
    $kind = [string](Get-iSOCPropertyValue -InputObject $setting -Path 'kind')
    if (-not $kind) { return 'missing required field kind.' }
    if ($kinds -cnotcontains $kind) { return "kind '$kind' is not one of $($kinds -join ', ')." }
    $name = [string](Get-iSOCPropertyValue -InputObject $setting -Path 'name')
    if (-not $name) { return 'missing required field name.' }
    if ($name -cne $kind) { return "name '$name' is not its kind '$kind': a Sentinel setting is named after its kind." }

    $properties = Get-iSOCPropertyValue -InputObject $setting -Path 'properties'
    if ($null -ne $properties -and $properties -isnot [System.Management.Automation.PSCustomObject]) { return 'properties is not an object.' }

    $lists = @{ EntityAnalytics = 'entityProviders'; Ueba = 'dataSources' }
    if (-not $lists.ContainsKey($kind)) { return }
    $field = $lists[$kind]
    $values = Get-iSOCPropertyValue -InputObject $properties -Path $field
    if ($null -eq $values) { return "missing required field properties.$field." }
    $names = @($values)
    if ($values -is [string] -or $names.Count -eq 0) { return "properties.$field is not a list of names." }
    foreach ($value in $names) {
        if ($value -isnot [string] -or -not $value.Trim()) { return "properties.$field is not a list of names." }
    }
}

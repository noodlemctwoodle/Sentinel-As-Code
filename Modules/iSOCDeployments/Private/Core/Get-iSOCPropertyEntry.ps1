#Requires -Version 7.2

<#
.SYNOPSIS
    Each property of a dictionary or an object, as a name and a value.

.DESCRIPTION
    Replaces Get-SafeProperty and Get-PropertyNames
    (847ef86:Tools/Export-Playbooks.ps1) where a walk needs every property
    rather than one by name: a key with a dot in it is read as it is, which
    Get-iSOCPropertyValue, splitting its path on dots, cannot do.

.NOTES
    File:         Modules/iSOCDeployments/Private/Core/Get-iSOCPropertyEntry.ps1
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

function Get-iSOCPropertyEntry {
    <#
    .SYNOPSIS
        Return each property of a dictionary or an object, in order, as
        Name and Value.

    .DESCRIPTION
        The keys of a dictionary (a parsed YAML or -AsHashtable JSON file)
        or the properties of an object (an API response). A string, a
        number, a list or nothing has none.

    .PARAMETER InputObject
        The value to walk.

    .OUTPUTS
        [pscustomobject] Name and Value, one per property.

    .EXAMPLE
        foreach ($entry in Get-iSOCPropertyEntry -InputObject $definition.triggers) { $entry.Name }
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [AllowNull()]
        [object] $InputObject
    )

    if ($null -eq $InputObject -or $InputObject -is [string] -or $InputObject -is [ValueType]) { return }
    if ($InputObject -is [System.Collections.IDictionary]) {
        foreach ($key in @($InputObject.Keys)) { [pscustomobject]@{ Name = [string]$key; Value = $InputObject[$key] } }
        return
    }
    if ($InputObject -is [System.Collections.IEnumerable]) { return }
    foreach ($property in $InputObject.PSObject.Properties) { [pscustomobject]@{ Name = $property.Name; Value = $property.Value } }
}

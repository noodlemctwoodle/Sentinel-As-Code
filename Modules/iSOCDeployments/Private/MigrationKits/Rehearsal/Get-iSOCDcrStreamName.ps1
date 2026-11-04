#Requires -Version 7.2

<#
.SYNOPSIS
    The stream to send to: the one asked for, or the rule's only one.

.DESCRIPTION
    A stream asked for must be declared; with none asked for, a rule with one
    stream uses it and one with several needs a choice.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/Rehearsal/Get-iSOCDcrStreamName.ps1
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

function Get-iSOCDcrStreamName {
    <#
    .SYNOPSIS
        The stream to send to: the one asked for, or the rule's only one.

    .DESCRIPTION
        A stream asked for must be one the rule declares. Without one, a rule
        declaring a single stream (the usual case for a migrated table) uses
        it; one declaring none or several throws, naming them.

    .PARAMETER Dcr
        The rule, as ARM returns it.

    .PARAMETER Requested
        The stream asked for.

    .OUTPUTS
        [string]

    .EXAMPLE
        Get-iSOCDcrStreamName -Dcr $dcr
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [object] $Dcr,

        [string] $Requested
    )

    $declarations = Get-iSOCPropertyValue -InputObject $Dcr -Path 'properties.streamDeclarations'
    $declared = @(if ($declarations) { $declarations.PSObject.Properties.Name })

    if ($Requested) {
        if ($declared -notcontains $Requested) {
            throw "Stream '$Requested' is not declared in this DCR. Declared: $($declared -join ', ')."
        }
        return $Requested
    }
    if ($declared.Count -eq 1) { return $declared[0] }
    if ($declared.Count -eq 0) { throw 'This DCR declares no streams.' }
    throw "This DCR declares $($declared.Count) streams ($($declared -join ', ')). Pass -StreamName to choose one."
}

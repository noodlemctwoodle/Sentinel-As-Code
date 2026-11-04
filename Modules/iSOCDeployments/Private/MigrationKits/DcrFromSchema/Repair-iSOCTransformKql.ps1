#Requires -Version 7.2

<#
.SYNOPSIS
    Replace the curly quotes and no-break spaces in a transform, and refuse one longer than a rule allows.

.DESCRIPTION
    The transform is code, so nothing else in it is changed.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/DcrFromSchema/Repair-iSOCTransformKql.ps1
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

function Repair-iSOCTransformKql {
    <#
    .SYNOPSIS
        Replace the curly quotes and no-break spaces in a transform, and
        refuse one longer than a rule allows.

    .DESCRIPTION
        A transform pasted from the portal, a wiki or a chat client picks up
        characters KQL refuses, and the failure arrives at deployment as a
        parse error at a character that looks right. Only those are
        replaced: collapsing whitespace, as for prose, could change a
        string literal. A transform longer than 15,360 characters (the
        documented limit) stops the run.

    .PARAMETER Transform
        The transform.

    .OUTPUTS
        [pscustomobject] Text and Applied.

    .EXAMPLE
        $check = Repair-iSOCTransformKql -Transform $transform
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Transform
    )

    $max = (Get-iSOCTableSchemaSetting).MaxTransformLength
    $applied = [System.Collections.Generic.List[string]]::new()

    $repaired = ConvertTo-iSOCStraightPunctuation -Text $Transform
    if ($repaired -ne $Transform) { $applied.Add('curly quotes or no-break spaces') }

    if ($repaired.Length -gt $max) {
        throw ("The transform is $($repaired.Length) characters; a data collection rule allows " +
            "$max. Move the logic into a workspace function, or trim it.")
    }

    [pscustomobject]@{
        Text    = $repaired
        Applied = $applied.ToArray()
    }
}

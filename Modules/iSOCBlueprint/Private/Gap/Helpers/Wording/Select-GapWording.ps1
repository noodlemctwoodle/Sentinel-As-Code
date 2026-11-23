#Requires -Version 7.6

<#
.SYNOPSIS
    One wording or the other by a count, such as has or have.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Helpers/Wording/Select-GapWording.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Gap Engine
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.
function Select-GapWording {
    <#
    .SYNOPSIS
        One wording or the other by a count, such as has or have.

    .DESCRIPTION
        Select-GapWording 1 'has' 'have' returns has; any other count returns
        have.

    .PARAMETER Count
        The count, read with ConvertTo-BlueprintDouble. A count of exactly 1
        selects the singular wording.

    .PARAMETER One
        The wording for a count of 1.

    .PARAMETER Many
        The wording for any other count.

    .OUTPUTS
        [string]
    #>
    [CmdletBinding()]
    param($Count, [string]$One, [string]$Many)
    if ((ConvertTo-BlueprintDouble $Count) -eq 1) { $One } else { $Many }
}

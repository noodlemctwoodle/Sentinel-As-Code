#Requires -Version 7.6

<#
.SYNOPSIS
    The four columns Azure Monitor Agent sends for a text log.

.DESCRIPTION
    TimeGenerated, RawData, FilePath and Computer: fixed by the agent, not
    taken from the table.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/ClassicToDcr/Get-iSOCDcrTextLogStreamColumn.ps1
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

function Get-iSOCDcrTextLogStreamColumn {
    <#
    .SYNOPSIS
        The four columns Azure Monitor Agent sends for a text log.

    .DESCRIPTION
        TimeGenerated (datetime), RawData, FilePath and Computer (string).
        The agent always sends these for a text log, whatever the
        destination table has.

    .OUTPUTS
        [pscustomobject[]] name and type.

    .EXAMPLE
        Get-iSOCDcrTextLogStreamColumn
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]], [array])]
    param()

    @(
        [pscustomobject]@{ name = 'TimeGenerated'; type = 'datetime' }
        [pscustomobject]@{ name = 'RawData'; type = 'string' }
        [pscustomobject]@{ name = 'FilePath'; type = 'string' }
        [pscustomobject]@{ name = 'Computer'; type = 'string' }
    )
}

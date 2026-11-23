#Requires -Version 7.6

<#
.SYNOPSIS
    Writes a progress line through the information stream.

.NOTES
    File:         Content/Workbooks/SentinelDataLake/SdlMigrationExport/Private/Console/Write-SdlStatus.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.2.0
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    Defines one function, dot-sourced by Export-SdlMigrationWorkbook.ps1
    (deprecated; to be replaced by the iSOCDeployments module).
#>

# Keeps the file help above from being read as the help of the function below.

function Write-SdlStatus {
    <#
    .SYNOPSIS
        Writes a progress line through the information stream.

    .DESCRIPTION
        Used instead of Write-Host so progress can be redirected or
        silenced. A heading is preceded by a blank line and is not
        indented.

    .PARAMETER Message
        The text to write.

    .PARAMETER Heading
        Write the message as a step heading.

    .OUTPUTS
        None.
    #>
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([void])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter()]
        [switch]$Heading
    )

    if ($Heading) {
        Write-Information -MessageData '' -InformationAction Continue
        Write-Information -MessageData $Message -InformationAction Continue
    } else {
        Write-Information -MessageData "  $Message" -InformationAction Continue
    }
}

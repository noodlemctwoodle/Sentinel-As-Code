#Requires -Version 7.6

<#
.SYNOPSIS
    Log a table of the requested solutions and where each stands.

.DESCRIPTION
    Copied from Get-SolutionUpdateReport
    (Deploy/content/Deploy-SentinelContentHub.ps1).

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentHub/Write-iSOCContentHubSolutionReport.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Write-iSOCContentHubSolutionReport {
    <#
    .SYNOPSIS
        One line per solution: installed and available versions, and
        Current, UPDATE, NEW or NOT FOUND.

    .DESCRIPTION
        An update is logged as a warning and a solution the catalogue does
        not have as an error.

    .PARAMETER SolutionStatuses
        From Get-iSOCContentHubSolutionStatus.

    .OUTPUTS
        None.

    .EXAMPLE
        Write-iSOCContentHubSolutionReport -SolutionStatuses $statuses
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $SolutionStatuses
    )

    Write-iSOCLog 'Solution Update Report' -Level Section
    Write-iSOCLog ('-' * 90)
    Write-iSOCLog ('{0,-45} {1,-15} {2,-15} {3,-12}' -f 'Solution', 'Installed', 'Available', 'Status')
    Write-iSOCLog ('-' * 90)

    foreach ($status in $SolutionStatuses) {
        $installed = if ($status.InstalledVersion) { $status.InstalledVersion } else { 'Not Installed' }
        $available = if ($status.AvailableVersion) { $status.AvailableVersion } else { 'N/A' }
        $statusText = switch ($status.Status) {
            'Installed' { 'Current' }
            'UpdateAvailable' { 'UPDATE' }
            'NotInstalled' { 'NEW' }
            'NotFound' { 'NOT FOUND' }
            default { $status.Status }
        }
        $level = switch ($status.Status) {
            'UpdateAvailable' { 'Warning' }
            'NotFound' { 'Error' }
            default { 'Info' }
        }
        Write-iSOCLog ('{0,-45} {1,-15} {2,-15} {3,-12}' -f $status.Name, $installed, $available, $statusText) -Level $level
    }

    Write-iSOCLog ('-' * 90)
}

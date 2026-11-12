#Requires -Version 7.6

<#
.SYNOPSIS
    Wait for a page's web part component to appear after a save.

.NOTES
    File:         Modules/iSOCBlueprint/Private/SharePoint/Pages/Wait-SacPageComponent.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, SharePoint site publisher
    Requires:     PowerShell 7.6+, PnP.PowerShell 3.4.1 (when the SharePoint functions are called)

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function Wait-SacPageComponent {
    <#
    .SYNOPSIS
        Wait for a freshly deployed web part to reach the site's component
        list. Returns whether it did.

    .PARAMETER ComponentId
        The component id, lower case without braces.

    .PARAMETER PageName
        An existing page to read the component list through.

    .PARAMETER WaitSeconds
        How long to wait at most.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [string] $ComponentId,
        [Parameter(Mandatory)] [string] $PageName,
        [int] $WaitSeconds = 300
    )
    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    while ($true) {
        try {
            if (Test-SacPageComponent -ComponentId $ComponentId -PageName $PageName) { return $true }
        }
        catch {
            # Shown, not swallowed: a lookup that fails every time would
            # otherwise look like a web part that never arrives.
            Write-Host "  Could not read the component list through $PageName.aspx: $($_.Exception.Message)" -ForegroundColor Yellow
        }
        if ((Get-Date) -ge $deadline) { return $false }
        Write-Host '  Chart web part not available yet; retrying in 20 seconds...'
        Start-Sleep -Seconds 20
    }
}

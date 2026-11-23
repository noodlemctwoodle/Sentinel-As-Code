#Requires -Version 7.6

<#
.SYNOPSIS
    True when a page carries the web part component.

.NOTES
    File:         Modules/iSOCBlueprint/Private/SharePoint/Pages/Test-SacPageComponent.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, SharePoint site publisher
    Requires:     PowerShell 7.6+, PnP.PowerShell 3.4.1 (when the SharePoint functions are called)

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Test-SacPageComponent {
    <#
    .SYNOPSIS
        True when a client-side component (web part) is in the component
        list of an existing page, matched by id ignoring braces and case.

    .DESCRIPTION
        Reads the list with Get-PnPAvailablePageComponents, the lookup the
        dashboard page already depends on. A raw POST to
        _api/web/GetClientSideWebParts through Invoke-PnPSPRestMethod sends
        the body 'null' when no -Content is given, so it is not used. A
        failed lookup throws rather than reading as "not there".

    .PARAMETER ComponentId
        The component id, lower case without braces.

    .PARAMETER PageName
        An existing page (name without .aspx) to read the list through.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [string] $ComponentId,
        [Parameter(Mandatory)] [string] $PageName
    )
    $components = @(Get-PnPAvailablePageComponents -Page $PageName -ErrorAction Stop)
    return [bool](@($components | Where-Object { $_ -and ([string]$_.Id).Trim('{}').ToLowerInvariant() -eq $ComponentId }).Count)
}

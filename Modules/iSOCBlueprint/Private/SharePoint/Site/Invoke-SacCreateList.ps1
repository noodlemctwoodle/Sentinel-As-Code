#Requires -Version 7.6

<#
.SYNOPSIS
    Create the findings list with its columns when it is missing.

.NOTES
    File:         Modules/iSOCBlueprint/Private/SharePoint/Site/Invoke-SacCreateList.ps1
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

function Invoke-SacCreateList {
    <#
    .SYNOPSIS
        Create a list or library, and accept a create call that timed out
        when the list exists afterwards.

    .DESCRIPTION
        Creating a library on a busy tenant can outlast PnP's 100-second
        HTTP timeout while SharePoint still finishes the job. When the call
        throws, the list is looked up for up to a minute; only if it never
        appears is the original error raised.

    .PARAMETER Url
        The list's site-relative URL.

    .PARAMETER Create
        The New-PnPList call.

    .OUTPUTS
        The list.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Url,
        [Parameter(Mandatory)] [scriptblock] $Create
    )
    try {
        $null = & $Create
        return (Get-PnPList -Identity $Url -ErrorAction Stop)
    }
    catch {
        $failure = $_
        for ($i = 0; $i -lt 6; $i++) {
            Start-Sleep -Seconds 10
            $list = Get-PnPList -Identity $Url -ErrorAction SilentlyContinue
            if ($list) {
                Write-Host "  Creating $Url reported '$($failure.Exception.Message)', but it exists; carrying on." -ForegroundColor Yellow
                return $list
            }
        }
        throw $failure
    }
}

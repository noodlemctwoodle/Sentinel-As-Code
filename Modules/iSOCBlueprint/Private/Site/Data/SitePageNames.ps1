#Requires -Version 7.6

<#
.SYNOPSIS
    Names of the dashboard page and the findings list on the SharePoint site.

.DESCRIPTION
    Defines $script:DashboardPage, $script:FindingsListUrl and $script:FindingsTitle.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Site/Data/SitePageNames.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, SharePoint site build
    Requires:     PowerShell 7.6+

    This file defines values rather than running.
#>

$script:DashboardPage = 'Dashboard'
$script:FindingsListUrl = 'Lists/SentinelFindings'
$script:FindingsTitle = 'Sentinel Findings'

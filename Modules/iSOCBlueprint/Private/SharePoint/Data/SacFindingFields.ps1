#Requires -Version 7.6

<#
.SYNOPSIS
    The findings list columns.

.DESCRIPTION
    Defines $script:SacFindingFields: internal column name to PnP field type.

.NOTES
    File:         Modules/iSOCBlueprint/Private/SharePoint/Data/SacFindingFields.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, SharePoint site publisher
    Requires:     PowerShell 7.6+, PnP.PowerShell 3.4.1 (when the SharePoint functions are called)

    This file defines values rather than running.
#>

# Findings list columns: internal name -> PnP field type.
$script:SacFindingFields = [ordered]@{
    FindingId    = 'Text'
    Severity     = 'Text'
    SeverityRank = 'Number'
    Category     = 'Text'
    Status       = 'Text'
    Evidence     = 'Note'
    Remediation  = 'Note'
    Learn        = 'URL'
    FirstSeen    = 'DateTime'
    LastSeen     = 'DateTime'
    ResolvedOn   = 'DateTime'
}

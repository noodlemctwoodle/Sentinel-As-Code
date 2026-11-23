#Requires -Version 7.6

<#
.SYNOPSIS
    Where the publisher puts a cut table's CSV.

.DESCRIPTION
    Defines $script:SacTablesUrl.

.NOTES
    File:         Modules/iSOCBlueprint/Private/PageSegments/Data/SacTablesUrl.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-13
    Version:      0.1.0
    Last Updated: 2026-11-13
    Component:    iSOC Blueprint, SharePoint page conversion
    Requires:     PowerShell 7.6+

    This file defines values rather than running.
#>

# Where the publisher puts a cut table's CSV: the tables/ folder of the
# assets library (SacSharePoint.ps1, $script:SacAssetsLibraryUrl).
$script:SacTablesUrl = '~site/BlueprintAssets/tables'

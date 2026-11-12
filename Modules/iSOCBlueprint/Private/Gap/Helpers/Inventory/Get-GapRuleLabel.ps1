#Requires -Version 7.6

<#
.SYNOPSIS
    A rule's display name for evidence text.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Helpers/Inventory/Get-GapRuleLabel.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, Gap Engine
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.
function Get-GapRuleLabel {
    param([object]$Rule)
    return Get-EvidenceName $Rule 'properties.displayName', 'name' 'Unnamed rule'
}

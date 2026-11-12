#Requires -Version 7.6

<#
.SYNOPSIS
    Order of effort labels, for sorting the roadmap.

.DESCRIPTION
    Defines $script:MaturityEffortRank: Low sorts before Medium before High.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Maturity/Data/MaturityEffortRank.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, Maturity Engine
    Requires:     PowerShell 7.6+

    This file defines a value rather than running.
#>

$script:MaturityEffortRank = @{ Low = 0; Medium = 1; High = 2 }

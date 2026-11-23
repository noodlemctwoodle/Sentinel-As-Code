#Requires -Version 7.6

<#
.SYNOPSIS
    ASIM parsers and the im/ASim function families are functions, not tables.

.DESCRIPTION
    Split from Get-KqlTableReferences.ps1 so each file holds one function.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Kql/Data/KqlFunctionNamePattern.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-09
    Version:      0.1.0
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+, SentinelCommon.Kql.ps1 (dot-sourced by the caller)

    This file sets a script-scope value rather than running.
#>

# ASIM parsers and the im/ASim function families are functions, not tables.
$script:KqlFunctionNamePattern = '^(_?ASim|_Im_|im)\w+$'

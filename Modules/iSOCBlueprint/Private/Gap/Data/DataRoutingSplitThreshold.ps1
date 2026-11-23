#Requires -Version 7.6

<#
.SYNOPSIS
    Volume above which the CEF, Syslog and Windows split rules fire.

.DESCRIPTION
    Defines $script:DataRoutingSplitThresholdGb30d for the data-routing gap
    checks (Test-CefSplitOpportunity, Test-SyslogSplitOpportunity,
    Test-WindowsEventXPathFilterOpportunity and the rules that share it).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Gap/Data/DataRoutingSplitThreshold.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, Gap Engine
    Requires:     PowerShell 7.6+

    This file defines a value rather than running.
#>

# All four data-routing rules use the same pattern: "is table X carrying
# enough volume to make the engineering effort to split worth it?". Five GB
# a day (150 GB per 30 days, compared as a 30-day-equivalent rate) is the
# conservative default; below that, the per-month saving from splitting
# probably can't pay for the DCR authoring time.
$script:DataRoutingSplitThresholdGb30d = 150.0

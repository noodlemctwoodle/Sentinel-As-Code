#Requires -Version 7.6

<#
.SYNOPSIS
    Short forms of the month names, for the date formatter.

.DESCRIPTION
    Defines $script:ShortMonth for the Blueprint renderer when the module loads.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Data/ShortMonth.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Requires:     PowerShell 7.6+

    This file defines a lookup table rather than running.
#>


# Dates inside the text the engines wrote (a finding's evidence, a remediation
# step, a criterion's note) read as they do everywhere else: 2026-10-14T23:16:38Z
# reads "14 Oct 2026 23:16 UTC", 2026-09-14 reads "14 Sep 2026" and 14 September
# 2026 reads "14 Sep 2026". Code spans stay as written.
$script:ShortMonth = @{
    January = 'Jan'; February = 'Feb'; March = 'Mar'; April = 'Apr'; June = 'Jun'; July = 'Jul'
    August = 'Aug'; September = 'Sep'; Sept = 'Sep'; October = 'Oct'; November = 'Nov'; December = 'Dec'
}

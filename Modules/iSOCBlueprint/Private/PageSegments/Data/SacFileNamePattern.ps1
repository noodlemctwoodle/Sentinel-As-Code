#Requires -Version 7.6

<#
.SYNOPSIS
    The pattern that finds a section file name (90-gap-analysis.md) in text.

.DESCRIPTION
    Defines $script:SacFileNamePattern.

.NOTES
    File:         Modules/iSOCBlueprint/Private/PageSegments/Data/SacFileNamePattern.ps1
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


# The Markdown pages refer to one another by file name (90-gap-analysis.md),
# which suits a folder of Markdown but not the site. These turn a file name
# into the section's title: from $script:SacSectionTitles (section id ->
# title), which the site build fills before it converts any page, or the id
# made readable when the build has not.
$script:SacFileNamePattern = '(?<![\w/.-])(?<id>\d{2}-[a-z0-9-]+)\.md\b'

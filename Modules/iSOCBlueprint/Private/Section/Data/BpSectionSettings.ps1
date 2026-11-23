#Requires -Version 7.6

<#
.SYNOPSIS
    The values the section converter shares: the schema version, the table chunk size and the comment markers it reads.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Section/Data/BpSectionSettings.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-13
    Version:      0.1.0
    Last Updated: 2026-11-13
    Component:    iSOC Blueprint, Section model conversion
    Requires:     PowerShell 7.6+

    This file defines values rather than running.
#>

$script:BpSectionSchemaVersion = 1

# The longest pipe table Markdig is given at once. It refuses one of about
# 2,700 short rows as too deeply nested; 500 leaves room for long cells.
$script:BpTableChunkRows = 500
$script:BpTableContinues = '<!-- bp:table-continues -->'
# Before a table or a line of figures a purpose-built graphic on the same
# page shows in full: it keeps its place in the Markdown and Word exports,
# and is flagged inGraphic so the SharePoint pages and the dashboard do not
# show it twice.
$script:BpShownInGraphic = '<!-- bp:shown-in-graphic -->'
# A purpose-built graphic with no Mermaid behind it (the top findings as
# cards): "<!-- bp:visual <kind> {json} -->", which Markdown does not show.
# It becomes a chart block of that kind with the JSON as its data.
$script:BpVisualComment = '^<!--\s*bp:visual\s+(?<kind>[a-z][a-z0-9-]*)\s+(?<json>\{.*\})\s*-->$'
# Before a callout, how serious what it says is: "<!-- bp:tone warning -->"
# (info, success, warning or critical). The site colours the callout by it;
# a callout without one is info.
$script:BpToneComment = '^<!--\s*bp:tone\s+(?<tone>info|success|warning|critical)\s*-->$'

#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'workbook-templates': writes workbook-templates.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Sentinel/Invoke-WorkbookTemplatesCapture.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Collector
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Invoke-WorkbookTemplatesCapture {
    <#
    .SYNOPSIS
        Capture 'workbook-templates': writes workbook-templates.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)

    $apiVersions = $Context.apiVersions
    $sentinelScope = $Context.sentinelScope

    $tpl = Invoke-SentinelRest -Path "$sentinelScope/contentTemplates?`$filter=properties/contentKind eq 'Workbook'" -ApiVersion $apiVersions.Sentinel
    Save-Json -FileName 'workbook-templates.json' -Data $tpl
}

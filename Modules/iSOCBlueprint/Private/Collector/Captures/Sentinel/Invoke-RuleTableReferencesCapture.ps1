#Requires -Version 7.6

<#
.SYNOPSIS
    Capture 'rule-table-references': writes rule-table-references.json, template-table-references.json.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Captures/Sentinel/Invoke-RuleTableReferencesCapture.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, Collector
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

function Invoke-RuleTableReferencesCapture {
    <#
    .SYNOPSIS
        Capture 'rule-table-references': writes rule-table-references.json, template-table-references.json.

    .PARAMETER Context
        The collector's run state: the Azure scope, API versions and paths the
        captures share.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)] [hashtable] $Context)


    # Which tables each rule and each template reads, resolved here with
    # the vendored Sentinel.Common KQL helpers so the gap engine and the
    # renderers read plain JSON.
    Save-Json -FileName 'rule-table-references.json' -Data (Get-RuleTableReferences -AlertRules $script:AlertRules)
    Save-Json -FileName 'template-table-references.json' -Data (Get-TemplateTableReferences -Templates $script:AlertRuleTemplates -AlertRules $script:AlertRules)
}

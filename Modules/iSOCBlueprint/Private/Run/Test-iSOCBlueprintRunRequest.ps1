#Requires -Version 7.6

<#
.SYNOPSIS
    Check that a New-iSOCBlueprint request makes sense and that the machine has what it needs.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Run/Test-iSOCBlueprintRunRequest.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.1.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, one-command run
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Test-iSOCBlueprintRunRequest {
    <#
    .SYNOPSIS
        Validate the request and the machine before a run does anything.

    .PARAMETER Run
        The run's shared state: the values New-iSOCBlueprint was called with
        and what each step has produced so far. Steps read and add to it.
        Adds Format (each format once), WantMarkdown and WantJson.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Run)

    $format = [string[]]@($Run.Format | Select-Object -Unique)
    $Run.Format = $format
    $Run.WantMarkdown = ($format -contains 'Markdown') -or ($format -contains 'Word')
    $Run.WantJson = ($format -contains 'Json') -or ($format -contains 'SharePoint')

    if ($Run.SiteUrl) {
        if ($format -notcontains 'SharePoint') { throw '-SiteUrl publishes the SharePoint format; add SharePoint to -Format.' }
        if (-not $Run.AccessToken -and -not ($Run.Interactive -and $Run.ClientId -and $Run.Tenant)) {
            throw '-SiteUrl needs -AccessToken, or -Interactive with -ClientId and -Tenant.'
        }
    }
    if ($Run.ChartImages -and -not $Run.WantMarkdown) { throw '-ChartImages draws the Markdown charts; add Markdown or Word to -Format.' }

    $steps = [System.Collections.Generic.List[string]]::new()
    if (-not $Run.SkipCollection) { $steps.Add('Collect') }
    $steps.Add('Render')
    if ($Run.ChartImages) { $steps.Add('ChartImage') }
    if ($format -contains 'Word') { $steps.Add('Word') }
    if ($format -contains 'SharePoint') { $steps.Add('Site') }
    if ($Run.SiteUrl) { $steps.Add('Publish') }

    Assert-iSOCBlueprintPrerequisite -Step $steps -For 'run'
}

#Requires -Version 7.6

<#
.SYNOPSIS
    What each step of a Blueprint run needs on the machine running it.

.DESCRIPTION
    One definition per requirement: the PowerShell version, the PowerShell
    Gallery modules and the command-line tools, with the steps each one
    serves and whether a step fails or only loses something without it.
    Test-iSOCBlueprintPrerequisite evaluates them; New-iSOCBlueprint checks
    them before it starts so a run does not fail half way.

    Steps:
      Collect     Export-iSOCBlueprintInventory
      Render      ConvertTo-iSOCBlueprint (JSON and Markdown)
      ChartImage  ConvertTo-iSOCBlueprintChartImage
      Word        Export-iSOCBlueprintWord
      Site        New-iSOCBlueprintSite
      Publish     Publish-iSOCBlueprintSite and Initialize-iSOCBlueprintSite

    Each public command that needs a module checks the steps it serves
    through Assert-iSOCBlueprintPrerequisite;
    Tests/iSOCBlueprint/Module.Tests.ps1 holds the commands and this list
    together.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Get-iSOCBlueprintRequirement.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-13
    Version:      0.1.3
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCBlueprintRequirement {
    <#
    .SYNOPSIS
        The requirement definitions, unevaluated.

    .OUTPUTS
        [pscustomobject] Name, Kind (PowerShell, Module or Tool), Step,
        Required, MinimumVersion, Command (tools: the names to look for)
        and Hint (how to install it, and what is lost without it when it is
        optional).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $all = 'Collect', 'Render', 'ChartImage', 'Word', 'Site', 'Publish'
    $req = {
        param($Name, $Kind, $Step, $Required, $MinimumVersion, $Command, $Hint)
        [pscustomobject]@{
            Name           = $Name
            Kind           = $Kind
            Step           = @($Step)
            Required       = [bool]$Required
            MinimumVersion = $MinimumVersion
            Command        = @($Command)
            Hint           = $Hint
        }
    }

    & $req 'PowerShell' 'PowerShell' $all $true '7.6' $null 'Install PowerShell 7.6 or later: https://aka.ms/powershell'
    foreach ($m in 'Az.Accounts', 'Az.OperationalInsights', 'Az.Resources', 'Az.Monitor', 'Az.SecurityInsights', 'Az.LogicApp') {
        & $req $m 'Module' 'Collect' $true $null $null "Install-Module $m -Scope CurrentUser, then sign in with Connect-AzAccount."
    }
    & $req 'Microsoft.Graph.Authentication' 'Module' 'Collect' $false $null $null 'Optional. Without it the Defender XDR custom detections are read through Azure PowerShell, which needs the CustomDetection.Read.All Graph permission on that identity.'
    & $req 'powershell-yaml' 'Module' 'Render' $true $null $null 'Install-Module powershell-yaml -Scope CurrentUser'
    & $req 'mmdc' 'Tool' 'ChartImage' $true $null 'mmdc' 'npm install -g @mermaid-js/mermaid-cli (needs Node.js).'
    & $req 'pandoc' 'Tool' 'Word' $true $null 'pandoc' 'macOS: brew install pandoc. Windows: winget install --id JohnMacFarlane.Pandoc. Linux: the pandoc package.'
    & $req 'LibreOffice' 'Tool' 'Word' $false $null @('soffice', 'libreoffice') 'Optional. Fills in the page numbers of the contents; without it the contents is a clickable list with no page numbers.'
    & $req 'python3 with uno' 'Tool' 'Word' $false $null 'python3' 'Optional, with LibreOffice. Ubuntu: the python3-uno package.'
    & $req 'PnP.PowerShell' 'Module' 'Publish' $true '3.4.1' $null 'Install-Module PnP.PowerShell -RequiredVersion 3.4.1 -Scope CurrentUser'
}

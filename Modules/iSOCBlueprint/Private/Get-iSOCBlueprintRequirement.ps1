#Requires -Version 7.2

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

    The module and version lists match the engine scripts' #Requires
    statements; Tests/iSOCBlueprint/Module.Tests.ps1 holds them together.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Get-iSOCBlueprintRequirement.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-13
    Version:      0.1.0
    Last Updated: 2026-10-13
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
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

    & $req 'PowerShell' 'PowerShell' $all $true '7.2' $null 'Install PowerShell 7.2 or later: https://aka.ms/powershell'
    & $req 'PowerShell' 'PowerShell' 'Publish' $true '7.4' $null 'Publishing and setting up the SharePoint site need PowerShell 7.4 or later (PnP.PowerShell 3).'
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

function Test-iSOCBlueprintRequirement {
    <#
    .SYNOPSIS
        Evaluate one requirement definition on this machine.

    .PARAMETER Requirement
        One object from Get-iSOCBlueprintRequirement.

    .OUTPUTS
        [pscustomobject] Name, Step, Required, Found, Version and Detail
        (where it was found, or the hint when it was not).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)] [pscustomobject] $Requirement)

    $found = $false
    $version = $null
    $where = $null
    $minimum = if ($Requirement.MinimumVersion) { [version]$Requirement.MinimumVersion } else { $null }

    switch ($Requirement.Kind) {
        'PowerShell' {
            $current = $PSVersionTable.PSVersion
            $version = $current.ToString()
            $found = ($null -eq $minimum) -or ([version]('{0}.{1}.{2}' -f $current.Major, $current.Minor, $current.Patch) -ge $minimum)
            $where = "PowerShell $version"
        }
        'Module' {
            $module = Get-Module -ListAvailable -Name $Requirement.Name | Sort-Object Version -Descending | Select-Object -First 1
            if ($module) {
                $version = $module.Version.ToString()
                $found = ($null -eq $minimum) -or ($module.Version -ge $minimum)
                $where = $module.ModuleBase
            }
        }
        'Tool' {
            $cmd = $null
            foreach ($name in $Requirement.Command) {
                $cmd = Get-Command -Name $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($cmd) { break }
            }
            if (-not $cmd -and $Requirement.Name -eq 'LibreOffice') {
                $mac = '/Applications/LibreOffice.app/Contents/MacOS/soffice'
                if (Test-Path -LiteralPath $mac) { $where = $mac; $found = $true }
            }
            if ($cmd) {
                $where = $cmd.Source
                $found = $true
                if ($Requirement.Name -eq 'python3 with uno') {
                    & $cmd.Source -c 'import uno' 2>$null | Out-Null
                    $found = ($LASTEXITCODE -eq 0)
                    if (-not $found) { $where = $null }
                }
            }
        }
    }

    $label = if ($minimum) { "$($Requirement.Name) $minimum+" } else { $Requirement.Name }
    [pscustomobject]@{
        PSTypeName = 'iSOCBlueprint.Prerequisite'
        Name       = $label
        Step       = $Requirement.Step
        Required   = $Requirement.Required
        Found      = [bool]$found
        Version    = $version
        Detail     = if ($found) { $where } else { $Requirement.Hint }
    }
}

#Requires -Version 7.2

<#
.SYNOPSIS
    Test-iSOCBlueprintPrerequisite: report what this machine can produce
    and what is missing.

.DESCRIPTION
    Evaluates the definitions in Private/Get-iSOCBlueprintRequirement.ps1.

.NOTES
    File:         Modules/iSOCBlueprint/Public/Test-iSOCBlueprintPrerequisite.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-13
    Version:      0.1.0
    Last Updated: 2026-10-13
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter and
    per-example detail lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Test-iSOCBlueprintPrerequisite {
    <#
    .SYNOPSIS
        Check the PowerShell version, modules and tools each Blueprint step
        needs.

    .DESCRIPTION
        Each step needs different things, and only what a run uses has to
        be installed:

          Collect     Az.* modules (Microsoft.Graph.Authentication optional)
          Render      powershell-yaml
          ChartImage  mmdc (@mermaid-js/mermaid-cli)
          Word        pandoc (LibreOffice with python3-uno optional, for
                      page numbers in the contents)
          Site        nothing beyond PowerShell 7.2
          Publish     PowerShell 7.4 and PnP.PowerShell 3.4.1, for
                      Publish-iSOCBlueprintSite and
                      Initialize-iSOCBlueprintSite

        Nothing is installed or changed.

    .PARAMETER Step
        Steps to check. Defaults to all of them.

    .PARAMETER Quiet
        Return $true when everything the steps require is present, else
        $false, instead of the list.

    .OUTPUTS
        [pscustomobject] One per requirement: Name, Step, Required, Found,
        Version and Detail (where it was found, or how to install it). With
        -Quiet, [bool].

    .EXAMPLE
        Test-iSOCBlueprintPrerequisite | Format-Table Name, Step, Required, Found, Version

        Shows everything at once.

    .EXAMPLE
        if (-not (Test-iSOCBlueprintPrerequisite -Step Word -Quiet)) { winget install --id JohnMacFarlane.Pandoc }

        Installs pandoc when the Word step would fail without it.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject], [bool])]
    param(
        [ValidateSet('Collect', 'Render', 'ChartImage', 'Word', 'Site', 'Publish')]
        [string[]] $Step = @('Collect', 'Render', 'ChartImage', 'Word', 'Site', 'Publish'),

        [switch] $Quiet
    )

    $results = @(foreach ($req in Get-iSOCBlueprintRequirement) {
            if (@($req.Step | Where-Object { $_ -in $Step }).Count -eq 0) { continue }
            $r = Test-iSOCBlueprintRequirement -Requirement $req
            $r.Step = @($r.Step | Where-Object { $_ -in $Step })
            $r
        })

    if ($Quiet) { return (@($results | Where-Object { $_.Required -and -not $_.Found }).Count -eq 0) }
    $results
}

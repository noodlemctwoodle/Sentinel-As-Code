#Requires -Version 7.6

<#
.SYNOPSIS
    Test-iSOCDeploymentPrerequisite: report what this machine is missing for
    each step.

.DESCRIPTION
    Evaluates the definitions in Private/Core/Get-iSOCRequirement.ps1.

.NOTES
    File:         Modules/iSOCDeployments/Public/Test-iSOCDeploymentPrerequisite.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-23
    Version:      0.4.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter and
    per-example detail lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Test-iSOCDeploymentPrerequisite {
    <#
    .SYNOPSIS
        Check the PowerShell version, modules and commands each step needs.

    .DESCRIPTION
        Only what a run uses has to be installed:

          Connect  Az.Accounts, signed in with Connect-AzAccount
          Read     powershell-yaml 0.4.12 or later, to read YAML content
          Deploy   Az.Resources, to deploy playbooks as ARM templates
          Import   git 2.x, to clone a community rule source
          Setup    Microsoft.Graph.Authentication, for the service
                   principal's directory role and Graph permission
          Migrate  Az.OperationalInsights, for the row counts and volume
                   the classic table migration reads

        Nothing is installed or changed; each command checks its own step
        before it starts and names what is missing.

    .PARAMETER Step
        Steps to check. Defaults to all of them.

    .PARAMETER Quiet
        Return $true when everything the steps need is present, else $false,
        instead of the list.

    .OUTPUTS
        [pscustomobject] One per requirement: Name, Step, Required, Found,
        Version and Detail (where it was found, or how to install it). With
        -Quiet, [bool].

    .EXAMPLE
        Test-iSOCDeploymentPrerequisite | Format-Table Name, Step, Found, Version

        Shows everything at once.

    .EXAMPLE
        if (-not (Test-iSOCDeploymentPrerequisite -Step Read -Quiet)) { Install-Module powershell-yaml -RequiredVersion 0.4.12 -Scope CurrentUser }

        Installs powershell-yaml when reading content would fail without it.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject], [bool])]
    param(
        [ValidateSet('Connect', 'Read', 'Deploy', 'Import', 'Setup', 'Migrate')]
        [string[]] $Step = @('Connect', 'Read', 'Deploy', 'Import', 'Setup', 'Migrate'),

        [switch] $Quiet
    )

    $results = @(foreach ($requirement in Get-iSOCRequirement) {
            if (@($requirement.Step | Where-Object { $_ -in $Step }).Count -eq 0) { continue }
            $result = Test-iSOCRequirement -Requirement $requirement
            $result.Step = @($result.Step | Where-Object { $_ -in $Step })
            $result
        })

    if ($Quiet) { return (@($results | Where-Object { $_.Required -and -not $_.Found }).Count -eq 0) }
    $results
}

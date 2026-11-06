#Requires -Version 7.2

<#
.SYNOPSIS
    What each step of iSOCDeployments needs on the machine running it.

.DESCRIPTION
    One definition per requirement: the PowerShell version and the
    PowerShell Gallery modules, with the steps each one serves. The module
    installs none of them; Test-iSOCDeploymentPrerequisite reports them and
    each command checks its own step before it starts.

    Steps:
      Connect   Connect-iSOCWorkspace and every command that calls Azure
      Read      reading YAML content from the repository
      Deploy    deploying ARM templates (playbooks), and the Bicep CLI for
                playbooks written in Bicep (asserted by the playbook reader
                only when it finds a .bicep file, so JSON playbooks need no
                Bicep)

    A content type names the requirements it needs in its Prerequisites,
    and Deploy-iSOCContent checks those for the types it is asked to
    deploy.

.NOTES
    File:         Modules/iSOCDeployments/Private/Core/Get-iSOCRequirement.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-23
    Version:      0.5.0
    Last Updated: 2026-11-06
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCRequirement {
    <#
    .SYNOPSIS
        The requirement definitions, unevaluated.

    .OUTPUTS
        [pscustomobject] Name, Kind (PowerShell, Module or Command), Step, Required,
        MinimumVersion and Hint (how to install it).

    .EXAMPLE
        Get-iSOCRequirement | Where-Object Step -contains 'Read'
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $all = 'Connect', 'Read', 'Deploy', 'Import', 'Setup', 'Migrate'
    $new = {
        param($Name, $Kind, $Step, $MinimumVersion, $Hint)
        [pscustomobject]@{
            Name           = $Name
            Kind           = $Kind
            Step           = @($Step)
            Required       = $true
            MinimumVersion = $MinimumVersion
            Hint           = $Hint
        }
    }

    & $new 'PowerShell' 'PowerShell' $all '7.2' 'Install PowerShell 7.2 or later: https://aka.ms/powershell'
    & $new 'Az.Accounts' 'Module' 'Connect' '2.0.0' 'Install-Module Az.Accounts -Scope CurrentUser, then sign in with Connect-AzAccount.'
    & $new 'powershell-yaml' 'Module' 'Read' '0.4.12' 'Install-Module powershell-yaml -RequiredVersion 0.4.12 -Scope CurrentUser'
    & $new 'Az.Resources' 'Module' 'Deploy' '6.0.0' 'Install-Module Az.Resources -Scope CurrentUser; playbooks deploy as ARM templates through it.'
    & $new 'git' 'Command' 'Import' '2.0.0' 'Install git 2.x and put it on the PATH: https://git-scm.com/downloads'
    & $new 'bicep' 'Command' 'Deploy' '0.30.0' 'Install the Bicep CLI and put it on the PATH: https://aka.ms/bicep/install (az bicep install puts it in ~/.azure/bin); Bicep playbooks are compiled with it.'
    & $new 'Az.OperationalInsights' 'Module' 'Migrate' '3.0.0' 'Install-Module Az.OperationalInsights -Scope CurrentUser; the classic table migration counts each table''s rows and volume through it.'
    & $new 'Microsoft.Graph.Authentication' 'Module' 'Setup' '2.0.0' 'Install-Module Microsoft.Graph.Authentication -Scope CurrentUser; the setup signs in to Microsoft Graph for the directory role and the Graph permission.'
}

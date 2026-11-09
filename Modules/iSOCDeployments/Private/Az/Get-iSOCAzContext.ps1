#Requires -Version 7.6

<#
.SYNOPSIS
    Read the current Az sign-in.

.NOTES
    File:         Modules/iSOCDeployments/Private/Az/Get-iSOCAzContext.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-23
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    Needs Az.Accounts when it runs. The module checks for it at that point
    (Assert-iSOCPrerequisite) instead of in #Requires, so it imports
    without it.

    Az cmdlets are only called from files under Private/Az/, so the rest of
    the module can be tested with these few wrappers mocked.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCAzContext {
    <#
    .SYNOPSIS
        Return the current Az context, or nothing when there is no sign-in.

    .OUTPUTS
        [Microsoft.Azure.Commands.Profile.Models.Core.PSAzureContext] or
        nothing.

    .EXAMPLE
        $az = Get-iSOCAzContext
    #>
    [CmdletBinding()]
    [OutputType([psobject])]
    param()

    Get-AzContext -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
}

#Requires -Version 7.2

<#
.SYNOPSIS
    Loader for the iSOCDeployments module.

.DESCRIPTION
    Dot-sources every private helper under Private/ (all folders, in path
    order) and then the public commands under Public/, one function per
    file, and exports the public ones. The files only define functions, so
    the order they load in does not matter.

    The only state the module keeps between calls is the workspace context
    Connect-iSOCWorkspace sets, which every command uses when it is not
    given -Context.

.NOTES
    File:         Modules/iSOCDeployments/iSOCDeployments.psm1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-23
    Version:      0.1.0
    Last Updated: 2026-10-23
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter and
    per-example detail lives on each command's own help block. The module's
    shipped version is ModuleVersion in iSOCDeployments.psd1.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:iSOCDeploymentsRoot = $PSScriptRoot
$script:iSOCContext = $null

foreach ($folder in 'Private', 'Public') {
    $root = Join-Path $PSScriptRoot $folder
    foreach ($file in Get-ChildItem -LiteralPath $root -Filter '*.ps1' -File -Recurse | Sort-Object FullName) {
        . $file.FullName
    }
}

Update-TypeData -TypeName 'iSOCDeployments.Context' -DefaultDisplayPropertySet 'WorkspaceName', 'ResourceGroup', 'SubscriptionId', 'Environment' -Force
Update-TypeData -TypeName 'iSOCDeployments.ContentType' -DefaultDisplayPropertySet 'Name', 'RepoFolder', 'Endpoint', 'Capabilities' -Force

$public = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'Public') -Filter '*.ps1' -File | ForEach-Object { $_.BaseName })
Export-ModuleMember -Function $public

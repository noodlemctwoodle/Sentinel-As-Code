#Requires -Version 7.2

<#
.SYNOPSIS
    Validate handler for playbooks.

.DESCRIPTION
    The check Deploy-CustomPlaybooks (Deploy/content/Deploy-CustomContent.ps1)
    makes before it deploys a template, with the same message. A file
    without a $schema is reported instead of failing the playbook, where
    strict mode made the script throw reading it (MIGRATION.md edit E9).

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/Playbook/Test-iSOCPlaybook.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.0
    Last Updated: 2026-11-03
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Test-iSOCPlaybook {
    <#
    .SYNOPSIS
        Say why a playbook cannot be deployed, if it cannot.

    .DESCRIPTION
        A file that does not parse fails the playbook; one whose $schema is
        not an ARM deployment template is skipped.

    .PARAMETER Item
        A repository item from Read-iSOCPlaybookRepo.

    .OUTPUTS
        [string] The problem; nothing when the template can be deployed.

    .EXAMPLE
        $issues = @(Test-iSOCPlaybook -Item $item)
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Item
    )

    if ($Item.ParseError) { return $Item.ParseError }
    $schema = [string](Get-iSOCPropertyValue -InputObject $Item.Data -Path '$schema')
    if (-not $schema -or $schema -notmatch 'deploymentTemplate') { return 'not an ARM deployment template.' }
}

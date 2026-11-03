#Requires -Version 7.2

<#
.SYNOPSIS
    ToRepoFile handler for playbooks: the template file a Logic App is
    written to.

.DESCRIPTION
    Copied from the write in Invoke-PlaybookExport (847ef86:Tools/Export-Playbooks.ps1). The template
    carries today's date, so the script rewrote a file it exported again
    however little had changed; here a file that would differ only in that
    date is left as it is (MIGRATION.md edit E27).

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/Playbook/ConvertTo-iSOCPlaybookFile.ps1
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

function ConvertTo-iSOCPlaybookFile {
    <#
    .SYNOPSIS
        Return the template text for a Logic App.

    .DESCRIPTION
        The template from ConvertTo-iSOCPlaybookTemplate, with the
        workspace's subscription, resource groups, name and id made
        parameters, as JSON with LF line endings and one final newline.
        When the repository's file is the same apart from its
        lastUpdateTime, that file's text is returned, so nothing changes.
        Each value that looks like a plain-text secret is warned about and
        added to -Warning: the export does not remove it, so it should be
        moved to Key Vault before the template is committed.

    .PARAMETER WorkspaceItem
        A Logic App as Read-iSOCPlaybookWorkspace returns it.

    .PARAMETER Context
        The workspace context.

    .PARAMETER Existing
        The template's text in the repository now, or nothing.

    .PARAMETER Author
        The author written into the metadata.

    .PARAMETER Warning
        A list each warning is added to.

    .OUTPUTS
        [string] The template's text.

    .EXAMPLE
        $text = ConvertTo-iSOCPlaybookFile -WorkspaceItem $app -Context $ctx -Author 'noodlemctwoodle'
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [psobject] $WorkspaceItem,

        [Parameter(Mandatory)]
        [psobject] $Context,

        [AllowNull()]
        [object] $Existing,

        [string] $Author = 'noodlemctwoodle',

        [System.Collections.Generic.List[string]] $Warning
    )

    $name = [string](Get-iSOCPropertyValue -InputObject $WorkspaceItem -Path 'name')
    $definition = Get-iSOCPropertyValue -InputObject $WorkspaceItem -Path 'properties.definition'
    $category = Get-iSOCPlaybookCategory -Definition $definition
    if (-not $Context.WorkspaceId) { Write-iSOCLog 'Workspace ID unavailable; hardcoded workspace IDs will stay in the exported definitions.' -Level Warning }
    $portable = Get-iSOCPortableContext `
        -SubscriptionId $Context.SubscriptionId `
        -PlaybookResourceGroup $Context.PlaybookResourceGroup `
        -WorkspaceResourceGroup $Context.ResourceGroup `
        -WorkspaceName $Context.WorkspaceName `
        -WorkspaceId $Context.WorkspaceId
    $template = ConvertTo-iSOCPlaybookTemplate -LogicApp $WorkspaceItem -Category $category -PlaybookName $name -AuthorName $Author -Context $portable

    foreach ($finding in @(Find-iSOCPlaintextSecret -Node $definition)) {
        $message = "'$name' holds a plain-text secret at $finding. Move it to Key Vault before committing."
        Write-iSOCLog "  $message" -Level Warning
        if ($null -ne $Warning) { $Warning.Add($message) }
    }

    $serialise = { param($Value) ($Value | ConvertTo-Json -Depth 100).Replace("`r`n", "`n") + "`n" }
    $text = & $serialise $template
    if ($Existing) {
        $date = $null
        try { $date = Get-iSOCPropertyValue -InputObject ([string]$Existing | ConvertFrom-Json -Depth 100 -ErrorAction Stop) -Path 'metadata.lastUpdateTime' }
        catch { $date = $null }
        if ($date -and [string]$date -ne $template.metadata.lastUpdateTime) {
            $template.metadata.lastUpdateTime = [string]$date
            if ((& $serialise $template) -ceq [string]$Existing) { return [string]$Existing }
        }
    }
    $text
}

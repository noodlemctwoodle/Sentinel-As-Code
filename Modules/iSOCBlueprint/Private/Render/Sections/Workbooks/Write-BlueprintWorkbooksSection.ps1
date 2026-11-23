#Requires -Version 7.6

<#
.SYNOPSIS
    Build the figures for and write 40-workbooks.md.

.DESCRIPTION
    A step of the Blueprint renderer. Steps run in order and pass their results
    to later ones through the render context, so this one may also prepare
    figures that a later page uses.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/Workbooks/Write-BlueprintWorkbooksSection.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.
function Write-BlueprintWorkbooksSection {
    <#
    .SYNOPSIS
        Build the figures for and write 40-workbooks.md.

    .PARAMETER Context
        The render context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the render context.
    $workbooksSaved = $Context.workbooksSaved

    # ---------------------------------------------------------------------------
    # Section: 40 / 50 / 60 / 70
    # ---------------------------------------------------------------------------
    $workbookTemplates = Read-BlueprintRawArray 'workbook-templates.json'
    $wbRows = $workbooksSaved | ForEach-Object {
        [pscustomobject]@{ Name = $_.properties.displayName; Category = $_.properties.category }
    }
    $wbUnsaved = [math]::Max(0, $workbookTemplates.Count - $workbooksSaved.Count)
    Write-BlueprintSection '40-workbooks.md' (@"
$(Format-Banner -Title 'Workbooks')

## Adoption

``````mermaid
pie showData title Workbook coverage
    "Saved (deployed)" : $($workbooksSaved.Count)
    "Available templates not deployed" : $wbUnsaved
``````

$(Format-BlueprintCount $workbooksSaved.Count) of $(Format-BlueprintCount $workbookTemplates.Count) available templates deployed in this workspace. The "templates not deployed" gap is where new visibility opportunities live.

## Saved workbooks

$(Format-BlueprintTable -Items $wbRows -Columns 'Name','Category')

## Templates available (Content Hub)

Total available: $(Format-BlueprintCount $workbookTemplates.Count)
"@)
}

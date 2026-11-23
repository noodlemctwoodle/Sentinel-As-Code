#Requires -Version 7.6

<#
.SYNOPSIS
    Build the figures for and write 70-content-hub.md.

.DESCRIPTION
    A step of the Blueprint renderer. Steps run in order and pass their results
    to later ones through the render context, so this one may also prepare
    figures that a later page uses.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/ContentHub/Write-BlueprintContentHubSection.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-16
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.
function Write-BlueprintContentHubSection {
    <#
    .SYNOPSIS
        Build the figures for and write 70-content-hub.md.

    .PARAMETER Context
        The render context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the render context.
    $cat = $Context.cat

    $contentPackages = Read-BlueprintRawArray 'content-packages.json'
    $contentCatalogue = Read-BlueprintRawArray 'content-product-packages.json'
    $repos = Read-BlueprintRawArray 'repositories.json'

    # Index catalogue versions by contentId so installed packages can join for
    # "update available" detection.
    $catalogueByContentId = @{}
    foreach ($p in $contentCatalogue) {
        $cid = $p.properties.contentId
        if ($cid) { $catalogueByContentId[$cid] = $p }
    }

    # One row per installed package with its status against the catalogue:
    # Deprecated or Not in catalogue (no more updates), Update available, or Up
    # to date; those needing attention first. With no catalogue capture there
    # is nothing to compare, so the status stays blank.
    $cpStatusRank = @{ 'Deprecated' = 0; 'Not in catalogue' = 1; 'Update available' = 2; 'Up to date' = 3; '' = 4 }
    $cpRows = @($contentPackages | Where-Object { $_ } | ForEach-Object {
            $installed = [string]$_.properties.version
            $cid = $_.properties.contentId
            $cat = if ($cid -and $catalogueByContentId.ContainsKey($cid)) { $catalogueByContentId[$cid] } else { $null }
            $latest = if ($cat) { [string]$cat.properties.version } else { '' }
            $deprecated = $cat -and $cat.properties.PSObject.Properties['isDeprecated'] -and [string]$cat.properties.isDeprecated -eq 'true'
            $status = if ($contentCatalogue.Count -eq 0) { '' }
            elseif (-not $cat) { 'Not in catalogue' }
            elseif ($deprecated) { 'Deprecated' }
            elseif ($latest -and $installed -and (Compare-BlueprintVersion $installed $latest) -lt 0) { 'Update available' }
            else { 'Up to date' }
            [pscustomobject]@{
                Name      = $_.properties.displayName
                Installed = $installed
                Latest    = $latest
                Status    = $status
                Source    = $_.properties.source.kind
            }
        } | Sort-Object @{ Expression = { $cpStatusRank[[string]$_.Status] } }, Name)
    $cpUpdates = @($cpRows | Where-Object Status -EQ 'Update available').Count
    $cpRetired = @($cpRows | Where-Object { $_.Status -in 'Deprecated', 'Not in catalogue' }).Count
    $omsSolutionRows = @(Read-BlueprintRawArray 'solutions-installed.json' | Where-Object { $_ } | ForEach-Object {
            $plan = if ($_.PSObject.Properties['plan'] -and $_.plan) { $_.plan } else { $null }
            $sp = if ($_.PSObject.Properties['properties'] -and $_.properties) { $_.properties } else { $null }
            [pscustomobject]@{
                Name         = $_.name
                Product      = if ($plan -and $plan.PSObject.Properties['product']) { $plan.product } else { '' }
                Publisher    = if ($plan -and $plan.PSObject.Properties['publisher']) { $plan.publisher } else { '' }
                Provisioning = if ($sp -and $sp.PSObject.Properties['provisioningState']) { $sp.provisioningState } else { '' }
                LastModified = if ($sp -and $sp.PSObject.Properties['lastModifiedTime']) { Format-DateUtc $sp.lastModifiedTime } else { '' }
            }
        })
    $repoRows = $repos | ForEach-Object {
        [pscustomobject]@{ Name = $_.properties.displayName; Type = $_.properties.repoType; Url = $_.properties.repository.url }
    }
    # Content-source distribution for the headline pie.
    $sourceCounts = @{}
    foreach ($p in $cpRows) {
        $s = if ($p.Source) { [string]$p.Source } else { 'Custom / unknown' }
        if (-not $sourceCounts.ContainsKey($s)) { $sourceCounts[$s] = 0 }
        $sourceCounts[$s]++
    }
    $sourcePieRows = $sourceCounts.GetEnumerator() | Sort-Object @{ Expression = 'Value'; Descending = $true }, Key | ForEach-Object {
        "    `"$($_.Key)`" : $($_.Value)"
    }

    # The installed packages as proportions for the SharePoint graphic: how
    # many are current and how many need attention, and where they come from.
    $cpStatusCount = { param([string]$S) @($cpRows | Where-Object { [string]$_.Status -eq $S }).Count }
    $sourceTone = @{ Solution = 'info'; Community = 'violet'; Standalone = 'teal' }
    $contentHubVisualLine = Format-VisualLine -Kind 'meters' -Data ([ordered]@{ meters = @(
                [ordered]@{ title = 'Installed packages'; caption = 'Against the Content Hub catalogue'; total = $cpRows.Count; parts = @(
                        [ordered]@{ label = 'Up to date'; value = (& $cpStatusCount 'Up to date'); tone = 'ok' }
                        [ordered]@{ label = 'Update available'; value = (& $cpStatusCount 'Update available'); tone = 'warn' }
                        [ordered]@{ label = 'Deprecated'; value = (& $cpStatusCount 'Deprecated'); tone = 'bad' }
                        [ordered]@{ label = 'Not in catalogue'; value = (& $cpStatusCount 'Not in catalogue'); tone = 'rose' }
                        [ordered]@{ label = 'Not checked'; value = (& $cpStatusCount ''); tone = 'neutral' }
                    )
                }
                [ordered]@{ title = 'By source'
                    caption       = 'Who publishes each package'
                    total         = $cpRows.Count
                    parts         = @($sourceCounts.GetEnumerator() | Sort-Object @{ Expression = 'Value'; Descending = $true }, Key | ForEach-Object {
                            [ordered]@{
                                label = [string]$_.Key
                                value = [int]$_.Value
                                tone  = $(if ($sourceTone.ContainsKey([string]$_.Key)) { $sourceTone[[string]$_.Key] } else { 'neutral' })
                            }
                        })
                }
            )
        })

    Write-BlueprintSection '70-content-hub.md' (@"
$(Format-Banner -Title 'Content Hub and Repositories')

## Source mix

``````mermaid
pie showData title Installed Content Hub packages by source
$contentHubVisualLine
$($sourcePieRows -join [Environment]::NewLine)
``````

<!-- bp:shown-in-graphic -->

**$(Format-BlueprintCount $cpRows.Count)** Content Hub $(Format-BlueprintPlural $cpRows.Count 'package' -NoCount) installed  ·  **$(Format-BlueprintCount $cpUpdates)** with an update available  ·  **$(Format-BlueprintCount $cpRetired)** deprecated or no longer listed  ·  **$(Format-BlueprintCount $sourceCounts.Count)** source $(Format-BlueprintPlural $sourceCounts.Count 'kind' -NoCount)

## Solutions installed

Every installed package against the Content Hub catalogue, those needing attention first. **Update available**: the catalogue has a newer version; update it from Content Hub to get the latest rules, parsers and workbooks. **Deprecated** or **Not in catalogue**: it no longer receives updates, and [SAC-DET-13] fires on either. **Up to date**: the installed version is the latest.

$(Format-BlueprintTable -Items $cpRows -Columns 'Name','Installed','Latest','Status','Source')

## Repositories

$(Format-BlueprintTable -Items $repoRows -Columns 'Name','Type','Url')

## Legacy management solutions

``Microsoft.OperationsManagement/solutions`` resources linked to the workspace: the pre-Content-Hub way Sentinel (``SecurityInsights``), Security and other packs were installed. They are harmless once Content Hub is in use, but they are the first place to look when a solution appears installed that Content Hub does not list.

$(Format-BlueprintTable -Items $omsSolutionRows -Columns 'Name','Product','Publisher','Provisioning','LastModified')

[Sentinel solutions (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/sentinel-solutions)
"@)

    # Left in the render context for later sections.
    $Context.p = $p
    if (Get-Variable -Name 's' -Scope 0 -ErrorAction Ignore) { $Context.s = $s }
}

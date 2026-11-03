#Requires -Version 7.2

<#
.SYNOPSIS
    Put a content type's items in the order they deploy.

.DESCRIPTION
    Replaces Get-PrioritizedFiles and the custom-before-community split in
    Deploy-CustomDetections (Deploy/content/Deploy-CustomContent.ps1).

.NOTES
    File:         Modules/iSOCDeployments/Private/Deploy/Get-iSOCDeployOrder.ps1
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

function Get-iSOCDeployOrder {
    <#
    .SYNOPSIS
        Return the items in deploy order: custom before Community, each
        with its prioritised items first.

    .DESCRIPTION
        Custom items deploy before Community ones and, within each, items
        whose path is in prioritizedcontentfiles (or under one) come first;
        otherwise the repository's order is kept. This is the order the
        script produced: it prioritised first and then moved Community
        rules to the end.

    .PARAMETER Run
        The deployment run, for the priorities.

    .PARAMETER Item
        The items, in repository order.

    .OUTPUTS
        The same items, reordered.

    .EXAMPLE
        $ordered = @(Get-iSOCDeployOrder -Run $run -Item $items)
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Run', Justification = 'Read inside the priority script block, which the analyser does not follow.')]
    [CmdletBinding()]
    [OutputType([psobject])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Run,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [psobject[]] $Item
    )

    $isPriority = {
        param($Entry)
        foreach ($p in $Run.Config.Prioritized) {
            if ($Entry.RelativePath -eq $p -or $Entry.RelativePath -like "$p*") { return $true }
        }
        $false
    }
    $ordered = foreach ($group in @(@($Item | Where-Object { $_.Source -ne 'Community' }), @($Item | Where-Object { $_.Source -eq 'Community' }))) {
        @($group | Where-Object { & $isPriority $_ })
        @($group | Where-Object { -not (& $isPriority $_) })
    }
    @($ordered)
}

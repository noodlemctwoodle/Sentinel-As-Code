#Requires -Version 7.2

<#
.SYNOPSIS
    Get-iSOCBlueprintWhatsNew: what is new, in preview and retiring in the
    SIEM and XDR platforms, from Microsoft Learn.

.DESCRIPTION
    Reads the Microsoft Sentinel and Microsoft Defender XDR What's new pages
    (Engine/Private/Get-WhatsNew.ps1) and returns their items. The collector
    runs the same function and saves the result as _raw/whats-new.json, which
    the renderer turns into the What's new page.

.NOTES
    File:         Modules/iSOCBlueprint/Public/Get-iSOCBlueprintWhatsNew.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-14
    Version:      0.1.0
    Last Updated: 2026-10-14
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter and
    per-example detail lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCBlueprintWhatsNew {
    <#
    .SYNOPSIS
        What is new, in preview and retiring in the SIEM and XDR platforms,
        from their What's new pages on Microsoft Learn.

    .DESCRIPTION
        Fetches the Microsoft Sentinel and Microsoft Defender XDR What's new
        pages from Microsoft Learn as Markdown and returns one list of items:
        product, month, title, status (Action needed, Retiring, Generally
        available, Preview or Update), summary, detail, the item's link on
        Learn, its first further-reading link, and for a retirement or a
        call to action the date it names. A page that cannot be reached is
        recorded in Sources with its error and the other is still read.

        This is the one Blueprint step that reads a public web page rather
        than the tenant. Export-iSOCBlueprintInventory runs it with the rest
        of the collection; use this command to refresh the list for an
        inventory already collected, or to read it on its own.

    .PARAMETER Months
        How many months back to keep, the current month included. Defaults
        to 12.

    .PARAMETER Path
        A workspace folder (holding _raw/) or a _raw folder. When given, the
        result is also saved there as whats-new.json, where the renderer
        reads it for the What's new page.

    .OUTPUTS
        [pscustomobject] FetchedUtc, Months, Sources (Product, Url, Ok,
        Error, Items) and Items (newest month first).

    .EXAMPLE
        (Get-iSOCBlueprintWhatsNew).Items | Where-Object Status -in 'Retiring', 'Action needed'

        The retirements and calls to action of the last 12 months.

    .EXAMPLE
        Get-iSOCBlueprintWhatsNew -Path ./SecurityDocs/law-sentinel-prod | Out-Null
        ConvertTo-iSOCBlueprint -Path ./SecurityDocs/law-sentinel-prod -Format Json

        Refreshes an inventory's What's new list, then renders the report
        again with it.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [ValidateRange(1, 60)]
        [int] $Months = 12,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string] $Path
    )

    process {
        . (Join-Path $script:iSOCBlueprintEngineRoot 'Private/Get-WhatsNew.ps1')
        $result = Get-WhatsNew -Months $Months
        if ($Path) {
            $target = Join-Path (Resolve-iSOCBlueprintRawPath -Path $Path) 'whats-new.json'
            if ($PSCmdlet.ShouldProcess($target, 'Save the What''s new list')) {
                $result | ConvertTo-Json -Depth 32 | Set-Content -LiteralPath $target -Encoding utf8
            }
        }
        $result
    }
}

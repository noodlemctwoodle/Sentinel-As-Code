#Requires -Version 7.2

<#
.SYNOPSIS
    ConvertTo-iSOCBlueprintChartImage: replace the Mermaid charts in the
    Markdown report with images.

.DESCRIPTION
    Runs Engine/Convert-MermaidToImage.ps1.

.NOTES
    File:         Modules/iSOCBlueprint/Public/ConvertTo-iSOCBlueprintChartImage.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-13
    Version:      0.1.0
    Last Updated: 2026-10-13
    Requires:     PowerShell 7.2+

    Needs mmdc (@mermaid-js/mermaid-cli) on PATH; see
    Test-iSOCBlueprintPrerequisite -Step ChartImage.

    This file defines functions rather than running. Per-parameter and
    per-example detail lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function ConvertTo-iSOCBlueprintChartImage {
    <#
    .SYNOPSIS
        Replace each Mermaid chart in the Markdown report with a PNG or SVG
        image.

    .DESCRIPTION
        For every workspace folder under Path, renders each fenced mermaid
        block in its Markdown pages to an image under <workspace>/assets/
        and rewrites the block as an image link. The Word report needs this
        for its charts (pandoc drops Mermaid fences), and so do Markdown
        viewers that do not draw Mermaid, such as Azure DevOps. Images are
        named by a hash of the chart, so a re-run only renders charts that
        changed. A chart mmdc cannot render is left as a fence, with a
        warning.

        The Markdown is changed in place. Render it again with
        ConvertTo-iSOCBlueprint to get the fences back.

    .PARAMETER Path
        Folder that holds one folder per workspace (not a workspace folder
        itself). Defaults to ./SecurityDocs under the current directory.

    .PARAMETER Format
        png (the default) or svg.

    .PARAMETER AssetsDirectory
        Name of the image folder inside each workspace folder. Defaults to
        assets.

    .PARAMETER Theme
        mmdc theme: default, dark, forest or neutral. Defaults to default.

    .PARAMETER Background
        Image background. Defaults to white, so a PNG reads on any page.

    .PARAMETER Width
        Render width in pixels. Defaults to 1400.

    .PARAMETER Scale
        Scale factor for PNG output. Defaults to 2.

    .OUTPUTS
        [pscustomobject] Path and Format.

    .EXAMPLE
        ConvertTo-iSOCBlueprintChartImage

        Renders the charts of every workspace under ./SecurityDocs as PNG.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $Path,

        [ValidateSet('png', 'svg')]
        [string] $Format = 'png',

        [string] $AssetsDirectory,

        [string] $Theme,

        [string] $Background,

        [int] $Width,

        [int] $Scale
    )

    $root = Resolve-iSOCBlueprintPath -Path $Path -Default 'SecurityDocs'
    $params = @{ Root = $root; Format = $Format }
    Copy-iSOCBlueprintParameter -BoundParameters $PSBoundParameters -Into $params -Name 'Theme', 'Background', 'Width', 'Scale' -Rename @{ AssetsDirectory = 'AssetsDir' }

    $null = Invoke-iSOCBlueprintEngine -Script 'Convert-MermaidToImage.ps1' -Parameters $params -BoundParameters $PSBoundParameters

    [pscustomobject]@{
        PSTypeName = 'iSOCBlueprint.ChartImages'
        Path       = $root
        Format     = $Format
    }
}

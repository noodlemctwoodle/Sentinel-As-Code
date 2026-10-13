#Requires -Version 7.2

<#
.SYNOPSIS
    ConvertTo-iSOCBlueprint: render an inventory as the section model
    (JSON) and the Markdown report.

.DESCRIPTION
    Offline: reads only the inventory folder. Runs
    Engine/Convert-SentinelInventoryToMarkdown.ps1.

.NOTES
    File:         Modules/iSOCBlueprint/Public/ConvertTo-iSOCBlueprint.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-13
    Version:      0.1.0
    Last Updated: 2026-10-13
    Requires:     PowerShell 7.2+

    The renderer itself requires powershell-yaml; see
    Test-iSOCBlueprintPrerequisite -Step Render.

    This file defines functions rather than running. Per-parameter and
    per-example detail lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function ConvertTo-iSOCBlueprint {
    <#
    .SYNOPSIS
        Render a Blueprint inventory as JSON (the section model), Markdown,
        or both.

    .DESCRIPTION
        Reads <Path>/_raw/ and writes, beside it:

          Json      sections/*.json and sections/index.json, the section
                    model the SharePoint site is built from and any other
                    tool can read
          Markdown  one page per section (00-overview.md onwards), the
                    report the Word document is made from

        Offline: nothing is read from Azure.

    .PARAMETER WorkspaceName
        Workspace name. Titles the pages and, when Path is omitted, names
        the folder under ./SecurityDocs.

    .PARAMETER Path
        The workspace folder that holds _raw/. Defaults to
        ./SecurityDocs/<WorkspaceName> under the current directory.

    .PARAMETER OutputPath
        Folder to write to. Defaults to Path.

    .PARAMETER Format
        Json, Markdown or both. Defaults to both.

    .PARAMETER ResourcesPath
        Folder of reference data (best-practices.json, the maturity
        criteria, the connector catalogue and the rest). Defaults to the
        copy inside the module; pass another to try changed rules.

    .OUTPUTS
        [pscustomobject] WorkspaceName, Path (where the output went),
        Format, and SectionsPath (the section model, when Json was
        written). Pipe it to New-iSOCBlueprintSite or
        Export-iSOCBlueprintWord.

    .EXAMPLE
        ConvertTo-iSOCBlueprint -WorkspaceName law-sentinel-prod

        Renders ./SecurityDocs/law-sentinel-prod/_raw/ as both formats.

    .EXAMPLE
        ConvertTo-iSOCBlueprint -WorkspaceName law-sentinel-prod -Path ./captures/prod -Format Json

        Writes only the section model, from an inventory kept elsewhere.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string] $WorkspaceName,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string] $Path,

        [string] $OutputPath,

        [ValidateSet('Markdown', 'Json')]
        [string[]] $Format = @('Markdown', 'Json'),

        [string] $ResourcesPath
    )

    process {
        $in = Resolve-iSOCBlueprintPath -Path $Path -Default (Join-Path 'SecurityDocs' $WorkspaceName)
        $out = Resolve-iSOCBlueprintPath -Path $OutputPath -Default $in
        $params = @{
            WorkspaceName = $WorkspaceName
            InputRoot     = $in
            OutputRoot    = $out
            OutputFormat  = @($Format)
        }
        if ($ResourcesPath) { $params.ResourcesRoot = Resolve-iSOCBlueprintPath -Path $ResourcesPath }

        $null = Invoke-iSOCBlueprintEngine -Script 'Convert-SentinelInventoryToMarkdown.ps1' -Parameters $params -BoundParameters $PSBoundParameters

        [pscustomobject]@{
            PSTypeName    = 'iSOCBlueprint.Report'
            WorkspaceName = $WorkspaceName
            Path          = $out
            Format        = @($Format)
            SectionsPath  = if ($Format -contains 'Json') { Join-Path $out 'sections' } else { $null }
        }
    }
}

#Requires -Version 7.2

<#
.SYNOPSIS
    Update-iSOCBlueprintConnectorCatalogue: refresh the data connector
    catalogue the module ships.

.DESCRIPTION
    A maintainer task. Runs Engine/Update-ConnectorCatalogue.ps1.

.NOTES
    File:         Modules/iSOCBlueprint/Public/Update-iSOCBlueprintConnectorCatalogue.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-13
    Version:      0.1.0
    Last Updated: 2026-10-13
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter and
    per-example detail lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Update-iSOCBlueprintConnectorCatalogue {
    <#
    .SYNOPSIS
        Refresh connector-catalogue.json, the data connector catalogue the
        module ships, from the Toolkit's connector data.

    .DESCRIPTION
        Downloads the connectors.json that the Sentinel as Code Toolkit
        (noodlemctwoodle/Sentinel-As-Code-Toolkit) builds: the Content Hub
        connectors and the tables each writes, from Microsoft's Solutions
        Analyzer. Writes the trimmed catalogue the gap analysis and the
        connector pages read. By default it overwrites the copy inside the
        module, so run it from a clone of the repository and commit the
        result; an installed module is refreshed by updating the module.

    .PARAMETER Source
        URL or local path of the Toolkit's connectors.json. Defaults to the
        Toolkit repository's main branch.

    .PARAMETER OutputPath
        The catalogue to write. Defaults to
        Engine/Private/Resources/connector-catalogue.json inside the module.

    .OUTPUTS
        [System.IO.FileInfo] The catalogue written, unless -WhatIf.

    .EXAMPLE
        Update-iSOCBlueprintConnectorCatalogue

        Refreshes the module's catalogue from the Toolkit.

    .EXAMPLE
        Update-iSOCBlueprintConnectorCatalogue -Source ../Sentinel-As-Code-Toolkit/data/connectors.json -WhatIf

        Shows what would be refreshed from a local Toolkit clone.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([System.IO.FileInfo])]
    param(
        [string] $Source,

        [string] $OutputPath
    )

    $target = Resolve-iSOCBlueprintPath -Path $OutputPath -Default (Join-Path $script:iSOCBlueprintEngineRoot 'Private/Resources/connector-catalogue.json')
    if (-not $PSCmdlet.ShouldProcess($target, 'Refresh the connector catalogue')) { return }

    $params = @{ OutputPath = $target }
    if ($Source) {
        $params.Source = if ($Source -match '^https?://') { $Source } else { Resolve-iSOCBlueprintPath -Path $Source }
    }
    $null = Invoke-iSOCBlueprintEngine -Script 'Update-ConnectorCatalogue.ps1' -Parameters $params -BoundParameters $PSBoundParameters
    Get-Item -LiteralPath $target
}

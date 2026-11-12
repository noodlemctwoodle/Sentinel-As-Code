#Requires -Version 7.6

<#
.SYNOPSIS
    The API versions the collector's captures call.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Collector/Setup/Get-CollectorApiVersion.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, Collector
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.

    API versions:
      - Azure Resource Graph : 2022-10-01
      - Everything else      : passed per capture through Invoke-SentinelRest,
                               so a provider version can be bumped in one place
                               without touching the captures
#>


function Get-CollectorApiVersion {
    <#
    .SYNOPSIS
        The provider API versions, by name.

    .OUTPUTS
        A hashtable: Sentinel, SentinelPreview, OperationalInsights, Tables and
        DataCollection.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    # API versions are hardcoded here rather than read from Blueprint.psd1.
    # Reading the manifest at script start was failing silently on the ADO Linux
    # agent, with $apiVersions arriving empty inside Try-Capture's child scope,
    # every subsequent REST call then fired without an api-version and Azure
    # returned 400 'MissingApiVersionParameter'. Inlining the table removes the
    # external file as a moving part. Keep these values in sync with the
    # 'ApiVersions' block in Blueprint.psd1 and the table in Blueprint-References.md.
    return @{
        Sentinel              = '2024-09-01'
        SentinelPreview       = '2024-10-01-preview'
        OperationalInsights   = '2025-02-01'
        Tables                = '2025-02-01'
        DataCollection        = '2023-03-11'
    }
}

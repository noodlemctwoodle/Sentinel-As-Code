#Requires -Version 7.6

<#
.SYNOPSIS
    Write one JSON file of the bundle, honouring -WhatIf.

.DESCRIPTION
    Helper for the SharePoint site build (Invoke-iSOCBlueprintSiteBuild).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Site/Helpers/Output/Write-SiteBundleJson.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, SharePoint site build
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Write-SiteBundleJson {
    <#
    .SYNOPSIS
        Write one JSON file of the bundle, honouring -WhatIf.

    .DESCRIPTION
        The write is skipped under -WhatIf and asks first under -Confirm: the
        function supports ShouldProcess, and the caller's $WhatIfPreference and
        $ConfirmPreference reach it as preference variables. The object is
        converted to JSON at a depth of 32 and written as UTF-8.

    .PARAMETER Path
        The JSON file to write.

    .PARAMETER Data
        The object to convert to JSON.

    .PARAMETER What
        The description of the action, passed to ShouldProcess.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] $Data,
        [Parameter(Mandatory)] [string] $What
    )
    if ($PSCmdlet.ShouldProcess($Path, $What)) {
        ($Data | ConvertTo-Json -Depth 32) | Set-Content -LiteralPath $Path -Encoding utf8
    }
}

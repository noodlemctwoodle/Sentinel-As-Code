#Requires -Version 7.6

<#
.SYNOPSIS
    Name an RBAC principal, falling back from its display name.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/Rbac/Format-BlueprintRbacPrincipal.ps1
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

# Principal fallback chain — DisplayName is empty for some assignments
# (deleted SPs, certain group types, MIs without a friendly name). Fall
# back to SignInName, then to the GUID ObjectId so the column always
# has content. An ObjectId-only row is a signal the principal may have
# been deleted but the role assignment lingers — itself a useful audit
# finding.
function Format-BlueprintRbacPrincipal {
    param($Row)
    if ($Row.DisplayName) { return [string]$Row.DisplayName }
    if ($Row.SignInName)  { return [string]$Row.SignInName }
    if ($Row.ObjectId)    { return "_(no display name)_ ``$($Row.ObjectId)``" }
    return '_(unknown)_'
}

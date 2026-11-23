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
    Version:      0.1.1
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Format-BlueprintRbacPrincipal {
    <#
    .SYNOPSIS
        Name an RBAC principal, falling back from its display name.

    .DESCRIPTION
        The display name is empty for some assignments (deleted service principals,
        certain group types, managed identities without a friendly name), so it
        falls back to the sign-in name, then to the object id, so the column always
        has content. An object-id-only row is a signal that the principal may have
        been deleted while the role assignment lingers, itself a useful audit
        finding. A row with none of them is shown as unknown.

    .PARAMETER Row
        The role assignment row.

    .OUTPUTS
        [string].
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param($Row)
    if ($Row.DisplayName) { return [string]$Row.DisplayName }
    if ($Row.SignInName) { return [string]$Row.SignInName }
    if ($Row.ObjectId) { return "_(no display name)_ ``$($Row.ObjectId)``" }
    return '_(unknown)_'
}

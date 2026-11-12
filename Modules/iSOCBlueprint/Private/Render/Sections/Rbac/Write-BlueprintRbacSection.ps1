#Requires -Version 7.6

<#
.SYNOPSIS
    Build the figures for and write 85-rbac.md.

.DESCRIPTION
    A step of the Blueprint renderer. Steps run in order and pass their results
    to later ones through the render context, so this one may also prepare
    figures that a later page uses.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Sections/Rbac/Write-BlueprintRbacSection.ps1
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
function Write-BlueprintRbacSection {
    <#
    .SYNOPSIS
        Build the figures for and write 85-rbac.md.

    .PARAMETER Context
        The render context: the figures earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the render context.
    $c = $Context.c
    $m = $Context.m
    $n = $Context.n

    # ---------------------------------------------------------------------------
    # Section: 85 — RBAC
    # ---------------------------------------------------------------------------
    $rbacWs = Read-BlueprintRawArray 'rbac-workspace.json'
    $rbacRg = Read-BlueprintRawArray 'rbac-resourcegroup.json'

    $wsRows = $rbacWs | ForEach-Object {
        [pscustomobject]@{ Principal = (Format-BlueprintRbacPrincipal $_); SignIn = [string](Get-BlueprintRawProperty $_ 'SignInName' ''); Type = (ConvertTo-BlueprintWords ([string]$_.ObjectType)); Role = $_.RoleDefinitionName }
    }
    # Counts per role by principal type, and the three views the access review
    # starts from: Sentinel roles, Log Analytics and monitoring roles, and the
    # roles that can change or delete the workspace.
    $roleCountRows = @($rbacWs | Where-Object { $_ } | Group-Object RoleDefinitionName | ForEach-Object {
        [pscustomobject]@{
            Role              = $_.Name
            Total             = $_.Count
            Users             = @($_.Group | Where-Object { $_.ObjectType -eq 'User' }).Count
            Groups            = @($_.Group | Where-Object { $_.ObjectType -eq 'Group' }).Count
            ServicePrincipals = @($_.Group | Where-Object { $_.ObjectType -eq 'ServicePrincipal' }).Count
        }
    } | Sort-Object @{ Expression = 'Total'; Descending = $true }, Role)
    $sentinelRoleRows = @($wsRows | Where-Object { $_.Role -match 'Sentinel' })
    $lawRoleRows = @($wsRows | Where-Object { $_.Role -match 'Log Analytics|Monitoring (Reader|Contributor)' })
    $highPrivRows = @($wsRows | Where-Object { $_.Role -in @('Owner', 'Contributor', 'User Access Administrator') })
    $rgRows = $rbacRg | ForEach-Object {
        [pscustomobject]@{ Principal = (Format-BlueprintRbacPrincipal $_); Type = (ConvertTo-BlueprintWords ([string]$_.ObjectType)); Role = $_.RoleDefinitionName }
    }

    # Build the RBAC flowchart. Group principals by role to keep the flow readable.
    # Mark broad-role paths (Owner / Contributor) as warnings via dotted edges.
    $rolesSeen = New-Object System.Collections.Generic.HashSet[string]
    foreach ($r in $rbacWs) {
        $role = $r.RoleDefinitionName
        if ($role) { [void]$rolesSeen.Add($role) }
    }
    $roleNodeLines = @()
    $roleIdMap = @{}
    $roleIdx = 0
    foreach ($role in $rolesSeen) {
        $roleIdx++
        $rId = "R$roleIdx"
        $roleIdMap[$role] = $rId
        $roleNodeLines += "        $rId[$role]"
    }

    # Per-role principal counts so the diagram doesn't list every individual SP.
    $principalsByRole = @{}
    foreach ($r in $rbacWs) {
        $role = $r.RoleDefinitionName
        $type = $r.ObjectType
        if (-not $principalsByRole.ContainsKey($role)) { $principalsByRole[$role] = @{ User = 0; Group = 0; ServicePrincipal = 0 } }
        if ($principalsByRole[$role].ContainsKey($type)) { $principalsByRole[$role][$type]++ }
    }

    $principalNodes = @()
    $principalEdges = @()
    $principalClicks = @()
    $prinIdx = 0
    foreach ($role in $rolesSeen) {
        foreach ($t in @('User', 'Group', 'ServicePrincipal')) {
            $n = $principalsByRole[$role][$t]
            if ($n -eq 0) { continue }
            $prinIdx++
            $prinId = "P$prinIdx"
            $principalNodes += "        $prinId[$(Format-BlueprintCount $n) $(Format-BlueprintPlural $n (ConvertTo-BlueprintWords $t).ToLowerInvariant() -NoCount)]"
            if ($role -in @('Owner', 'Contributor')) {
                $sentId = if ($t -eq 'ServicePrincipal') { 'sac-gov-05' } else { 'sac-gov-06' }
                $principalEdges += "    $prinId -.->|broad| $($roleIdMap[$role])"
                $principalClicks += "    click $prinId href ""90-gap-analysis.md#$sentId"" ""$($sentId.ToUpper()): broad role recommendation"""
            } else {
                $principalEdges += "    $prinId --> $($roleIdMap[$role])"
            }
        }
    }

    # The assignments as data for the SharePoint graphic: every role in a band
    # (broad roles, Microsoft Sentinel roles, Log Analytics and monitoring, the
    # rest), with its users, groups and service principals.
    $accessBand = { param([string]$Role)
        if ($Role -in 'Owner', 'Contributor', 'User Access Administrator') { 'broad' }
        elseif ($Role -like 'Microsoft Sentinel*') { 'sentinel' }
        elseif ($Role -like 'Log Analytics*' -or $Role -like 'Monitoring*') { 'monitor' }
        else { 'other' }
    }
    $accessRoles = { param([string]$Band)
        @($rolesSeen | Where-Object { (& $accessBand $_) -eq $Band } | ForEach-Object {
            $c = $principalsByRole[$_]
            [ordered]@{ role = [string]$_; users = [int]$c['User']; groups = [int]$c['Group']; servicePrincipals = [int]$c['ServicePrincipal'] }
        } | Sort-Object { -($_.users + $_.groups + $_.servicePrincipals) }, { $_.role })
    }
    $accessVisualLine = Format-VisualLine -Kind 'access' -Data ([ordered]@{ bands = @(
        [ordered]@{ name = 'Broad roles'; tone = 'bad'; findings = @(@('SAC-GOV-05', 'SAC-GOV-06') | Where-Object { $script:FiredFindingIds.ContainsKey($_) }); roles = @(& $accessRoles 'broad') }
        [ordered]@{ name = 'Microsoft Sentinel roles'; tone = 'ok'; findings = @(); roles = @(& $accessRoles 'sentinel') }
        [ordered]@{ name = 'Log Analytics and monitoring'; tone = 'info'; findings = @(); roles = @(& $accessRoles 'monitor') }
        [ordered]@{ name = 'Other roles'; tone = 'neutral'; findings = @(); roles = @(& $accessRoles 'other') }
    ) })

    # Headline figures for the access review: how many assignments and to whom,
    # then the ones that carry risk. A principal is counted once however many
    # roles it holds; one with neither a display name nor a sign-in name is
    # deleted or not readable by the collector.
    $rbacValid = @($rbacWs | Where-Object { $_ })
    $rbacPrincipals = @($rbacValid | Group-Object { $oid = [string](Get-BlueprintRawProperty $_ 'ObjectId' ''); if ($oid) { $oid } else { [string](Get-BlueprintRawProperty $_ 'DisplayName' '') + '|' + [string](Get-BlueprintRawProperty $_ 'SignInName' '') } })
    $rbacOfType = { param($t) @($rbacPrincipals | Where-Object { [string](Get-BlueprintRawProperty $_.Group[0] 'ObjectType' '') -eq $t }).Count }
    $rbacHigh = @($rbacValid | Where-Object { $_.RoleDefinitionName -in 'Owner', 'Contributor', 'User Access Administrator' }).Count
    $rbacHighPct = if ($rbacValid.Count) { [math]::Round(100 * $rbacHigh / $rbacValid.Count) } else { 0 }
    $rbacOwners = @($rbacValid | Where-Object RoleDefinitionName -EQ 'Owner').Count
    $rbacSentinel = @($rbacValid | Where-Object { [string]$_.RoleDefinitionName -like 'Microsoft Sentinel*' }).Count
    $rbacGuests = @($rbacPrincipals | Where-Object { [string](Get-BlueprintRawProperty $_.Group[0] 'SignInName' '') -match '#EXT#' }).Count
    $rbacUnnamed = @($rbacPrincipals | Where-Object { -not (Get-BlueprintRawProperty $_.Group[0] 'DisplayName' '') -and -not (Get-BlueprintRawProperty $_.Group[0] 'SignInName' '') }).Count

    Write-BlueprintSection '85-rbac.md' (@"
$(Format-Banner -Title "Access Control (RBAC)")

$(Format-BlueprintPlural $rbacWs.Count 'workspace-scope assignment') across $(Format-BlueprintPlural $rolesSeen.Count 'distinct role'). Broad roles (Owner and Contributor) are marked out below; see [SAC-GOV-06] and [SAC-GOV-05] in the gap analysis.

**$(Format-BlueprintCount $rbacValid.Count)** assignments at workspace scope  ·  **$(Format-BlueprintCount @($rbacRg | Where-Object { $_ }).Count)** at resource-group scope  ·  **$(Format-BlueprintCount $rbacPrincipals.Count)** distinct principals  ·  **$(Format-BlueprintCount (& $rbacOfType 'User'))** users  ·  **$(Format-BlueprintCount (& $rbacOfType 'Group'))** groups  ·  **$(Format-BlueprintCount (& $rbacOfType 'ServicePrincipal'))** service principals

**$(Format-BlueprintCount $rbacHigh)** high-privilege assignments  ·  **$rbacHighPct%** of assignments high-privilege  ·  **$(Format-BlueprintCount $rbacOwners)** Owner assignments  ·  **$(Format-BlueprintCount $rbacSentinel)** Microsoft Sentinel role assignments  ·  **$(Format-BlueprintCount $rbacGuests)** guest accounts  ·  **$(Format-BlueprintCount $rbacUnnamed)** principals with no name (deleted or not readable)

## Who-grants-what-to-whom

``````mermaid
flowchart LR
$accessVisualLine
    subgraph PRIN["Principals"]
        direction TB
$($principalNodes -join [Environment]::NewLine)
    end

    subgraph ROLES["Roles at workspace scope"]
        direction TB
$($roleNodeLines -join [Environment]::NewLine)
    end

$($principalEdges -join [Environment]::NewLine)

    classDef sentinelRole fill:#1a3b1a,stroke:#3a3,color:#dfd
    classDef broadRole fill:#5b1a1a,stroke:#a33,color:#fdd
$(($rolesSeen | ForEach-Object {
    if ($_ -in @('Owner', 'Contributor')) { "    class $($roleIdMap[$_]) broadRole" }
    elseif ($_ -like 'Microsoft Sentinel*') { "    class $($roleIdMap[$_]) sentinelRole" }
}) -join [Environment]::NewLine)
$($principalClicks -join [Environment]::NewLine)
``````

## Assignments by role

$(Format-BlueprintTable -Items $roleCountRows -Columns 'Role','Total','Users','Groups','ServicePrincipals')

## Microsoft Sentinel role assignments

$(Format-BlueprintTable -Items $sentinelRoleRows -Columns 'Principal','SignIn','Type','Role' -EmptyMessage '_No Microsoft Sentinel role is assigned at workspace scope._')

## Log Analytics and monitoring role assignments

$(Format-BlueprintTable -Items $lawRoleRows -Columns 'Principal','SignIn','Type','Role' -EmptyMessage '_No Log Analytics or monitoring role is assigned at workspace scope._')

## High-privilege assignments (Owner, Contributor, User Access Administrator)

These roles can change or delete the workspace and everything in it, or grant access to others. Defender XDR portal roles are granted in Microsoft Entra ID and the Defender portal at tenant scope and cannot be read from the workspace.

$(Format-BlueprintTable -Items $highPrivRows -Columns 'Principal','SignIn','Type','Role' -EmptyMessage '_No Owner, Contributor or User Access Administrator assignment at workspace scope._')

## At workspace scope

$(Format-BlueprintTable -Items $wsRows -Columns 'Principal','SignIn','Type','Role')

## At resource group scope

$(Format-BlueprintTable -Items $rgRows -Columns 'Principal','Type','Role')

[Sentinel roles (Microsoft Learn)](https://learn.microsoft.com/azure/sentinel/roles)
"@)

    # Left in the render context for later sections.
    if (Get-Variable -Name 'n' -Scope 0 -ErrorAction Ignore) { $Context.n = $n }
    $Context.r = $r
    if (Get-Variable -Name 'rid' -Scope 0 -ErrorAction Ignore) { $Context.rid = $rid }
    $Context.t = $t
}

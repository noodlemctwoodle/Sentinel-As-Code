#Requires -Version 7.6

<#
.SYNOPSIS
    Compare-iSOCContent: find what changed in the workspace and not in the
    repository.

.DESCRIPTION
    The detection half of Tools/Test-SentinelRuleDrift.ps1. The script's
    -SkipContentHub, -SkipCustom and -SkipOrphans become -ExcludeSource,
    -Solutions and -SeveritiesToInclude become -Solution and -Severity, and
    -ResourceGroup, -Workspace, -Region and -IsGov come from
    Connect-iSOCWorkspace. Absorbing the changes into the repository is
    Sync-iSOCContent, and writing the report Export-iSOCDriftReport
    (MIGRATION.md edit E24).

.NOTES
    File:         Modules/iSOCDeployments/Public/Compare-iSOCContent.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter and
    per-example detail lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Compare-iSOCContent {
    <#
    .SYNOPSIS
        Compare the connected workspace's content with its source of truth,
        and say what drifted.

    .DESCRIPTION
        Every item in the workspace is classed by where its source of truth
        is, then compared with it field by field, using the fields and
        comparers its content type names (Get-iSOCContentType shows them):

        - InSync: it matches;
        - PortalEdit: it has a file in the repository and was changed in the
          portal;
        - ContentHubCustomised: it came from a Content Hub template and was
          changed from it;
        - PortalOnly: nothing in the repository or Content Hub accounts for
          it (an orphan);
        - Managed: Microsoft manages it, and it is not compared;
        - Skipped: filtered out or excluded, with the reason.

        For analytics rules, a rule whose id is a repository rule's is
        governed by that file even when it also came from a template, so a
        rule absorbed into the repository stays governed by it. The file is
        compared as deploy would send it. Enabled is not compared: deploy
        sends rules disabled for missing dependencies and Community rules,
        and Content Hub deployment can send them all disabled. Nothing is
        changed in the workspace or the repository.

    .PARAMETER ContentType
        The content types to compare, by name or wildcard. Defaults to every
        type the module can compare: analytics rules, so far.

    .PARAMETER Solution
        Compare only the Content Hub rules of these solutions, by display
        name. Repository and orphan rules are not affected.

    .PARAMETER Severity
        Compare only rules of these severities. Defaults to all four.

    .PARAMETER ExcludeSource
        Leave out the rules of these sources, which are then reported as
        Skipped: ContentHub, Custom (governed by a repository file) or
        Orphan.

    .PARAMETER Context
        The workspace to compare. Defaults to the one Connect-iSOCWorkspace
        connected.

    .PARAMETER RepoPath
        The repository root. Defaults to the repository the current folder
        is in.

    .OUTPUTS
        [pscustomobject] iSOCDeployments.DriftResult: GeneratedAt, Workspace,
        ResourceGroup, RepoPath, ContentTypes, Items (one
        iSOCDeployments.DriftItem per workspace item: ContentType, Name,
        ResourceName, Kind, Source, State, Reason, SourceRef, Solution,
        Enabled, Modifications), Summary (the counts the drift report
        shows) and HasDrift (anything PortalEdit, ContentHubCustomised or
        PortalOnly).

    .EXAMPLE
        Connect-iSOCWorkspace -ResourceGroup rg-sentinel -WorkspaceName law-sentinel
        $drift = Compare-iSOCContent
        $drift.Items | Where-Object State -ne InSync | Format-Table Name, State, Reason

        Lists every rule that is not as its source says, and why.

    .EXAMPLE
        $drift = Compare-iSOCContent -Severity High, Medium
        $drift | Sync-iSOCContent | Export-iSOCDriftReport
        exit [int]$drift.HasDrift

        The drift pipeline: compare, write the changes into the repository,
        write the report, and fail the step when anything drifted.

    .EXAMPLE
        Compare-iSOCContent -Solution 'Microsoft Defender XDR' -ExcludeSource Orphan

        Compares one solution's Content Hub rules and the repository's own,
        leaving portal-only rules out.
    #>
    [CmdletBinding()]
    [OutputType('iSOCDeployments.DriftResult')]
    param(
        [SupportsWildcards()]
        [string[]] $ContentType,

        [string[]] $Solution = @(),

        [ValidateSet('High', 'Medium', 'Low', 'Informational')]
        [string[]] $Severity = @('High', 'Medium', 'Low', 'Informational'),

        [ValidateSet('ContentHub', 'Custom', 'Orphan')]
        [string[]] $ExcludeSource = @(),

        [psobject] $Context,

        [string] $RepoPath
    )

    $ctx = Resolve-iSOCContext -Context $Context
    $repo = Resolve-iSOCRepoPath -RepoPath $RepoPath

    $types = @(Get-iSOCContentTypeDefinition -Name $ContentType)
    if ($ContentType) {
        $cannot = @($types | Where-Object { $_.Capabilities -notcontains 'Compare' })
        if ($cannot.Count -gt 0) { throw "The module cannot compare $(($cannot | ForEach-Object { $_.Name }) -join ', ') yet." }
    } else {
        $types = @($types | Where-Object { $_.Capabilities -contains 'Compare' })
    }
    Assert-iSOCPrerequisite -Step Connect, Read

    $run = New-iSOCDriftRun -Context $ctx -RepoPath $repo -Options @{ Solution = $Solution; Severity = $Severity; ExcludeSource = $ExcludeSource }
    $items = [System.Collections.Generic.List[object]]::new()
    $total = 0
    foreach ($type in $types) {
        $workspaceItems = @(Invoke-iSOCContentTypeHandler -ContentType $type -Handler ReadWorkspace -Parameters @{ Context = $ctx; ContentType = $type })
        $total += $workspaceItems.Count
        foreach ($workspaceItem in $workspaceItems) {
            $source = Invoke-iSOCContentTypeHandler -ContentType $type -Handler Classify -Parameters @{ Run = $run; ContentType = $type; WorkspaceItem = $workspaceItem }
            if ($source.State) {
                $items.Add((New-iSOCDriftItem -ContentType $type.Name -Item $workspaceItem -Source $source -State $source.State))
                continue
            }
            $actual = Invoke-iSOCContentTypeHandler -ContentType $type -Handler ToComparable -Parameters @{ WorkspaceItem = $workspaceItem }
            $modifications = @(Compare-iSOCContentBody -ContentType $type -Expected $source.Expected -Actual $actual)
            $state = if ($modifications.Count -eq 0) { 'InSync' } elseif ($source.Source -eq 'ContentHub') { 'ContentHubCustomised' } else { 'PortalEdit' }
            $items.Add((New-iSOCDriftItem -ContentType $type.Name -Item $workspaceItem -Source $source -State $state -Modification $modifications))
        }
    }

    $count = { param([scriptblock] $Filter) @($items | Where-Object $Filter).Count }
    $summary = [ordered]@{
        totalDeployed   = $total
        contentHubClean = & $count { $_.Source -eq 'ContentHub' -and $_.State -eq 'InSync' }
        contentHubDrift = & $count { $_.State -eq 'ContentHubCustomised' }
        customClean     = & $count { $_.Source -eq 'Custom' -and $_.State -eq 'InSync' }
        customDrift     = & $count { $_.State -eq 'PortalEdit' }
        orphan          = & $count { $_.State -eq 'PortalOnly' }
        managed         = & $count { $_.State -eq 'Managed' }
        skipped         = & $count { $_.State -eq 'Skipped' }
    }

    $drift = [pscustomobject]@{
        PSTypeName    = 'iSOCDeployments.DriftResult'
        GeneratedAt   = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        Workspace     = $ctx.WorkspaceName
        ResourceGroup = $ctx.ResourceGroup
        RepoPath      = $repo
        ContentTypes  = @($types | ForEach-Object { $_.Name })
        Items         = @($items)
        Summary       = $summary
        HasDrift      = ($summary.contentHubDrift + $summary.customDrift + $summary.orphan) -gt 0
    }
    Write-iSOCDriftSummary -Drift $drift
    $drift
}

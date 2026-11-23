#Requires -Version 7.6

<#
.SYNOPSIS
    Export-iSOCContent: write the workspace's content into the repository,
    ready to deploy.

.DESCRIPTION
    Replaces Tools/Export-SentinelWorkbooks.ps1 and the playbook exporter
    847ef86:Tools/Export-Playbooks.ps1. Both scripts' -ResourceGroup,
    -Workspace, -Region, -PlaybookResourceGroup and -IsGov come from
    Connect-iSOCWorkspace; -Filter and -NameFilter become -Name, -BasePath
    and -OutputPath -Path, and -OnlyMissing is the default
    (MIGRATION.md edit E25). Playbooks are written as Bicep unless
    -Format Json is given (edit E48).

.NOTES
    File:         Modules/iSOCDeployments/Public/Export-iSOCContent.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.2.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter and
    per-example detail lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Export-iSOCContent {
    <#
    .SYNOPSIS
        Write workbooks and playbooks from the connected workspace into the
        repository, in the shape Deploy-iSOCContent deploys.

    .DESCRIPTION
        For each content type that can be exported (workbooks and playbooks,
        so far), every item in the workspace is classed by its source, as
        Compare-iSOCContent classes it, and:

        - one the repository already has (by workbookId, or by
          PlaybookName) is left alone, unless -Force is given, when it is
          written over in its own file or folder, wherever that is;
        - one only the workspace has is written to a new file or folder:
          Content/Workbooks/<Name>/ or Content/Playbooks/<Trigger>/<Name>.bicep
          (.json with -Format Json); a playbook the repository already has
          keeps its file's format;
        - one a Content Hub solution installed is skipped unless
          -IncludeContentHub is given, since it belongs to its solution;
        - a file or folder that holds another item is never written over,
          and nor is one an earlier item of the run was written to.

        Environment values are made portable: a workbook's workspace
        resource id becomes the repository's placeholder, and a playbook's
        subscription, resource groups, workspace name and id become ARM
        expressions and parameters, written by the module's own Bicep
        writer, so no Bicep CLI is needed. A file whose content would not change
        is left alone. Nothing is deleted, and the workspace is not
        changed. With -WhatIf everything is read and nothing written, and
        each item says what would be.

    .PARAMETER ContentType
        The content types to export, by name or wildcard. Defaults to every
        type the module can export.

    .PARAMETER Name
        Export only the items whose display name (a workbook's) or name (a
        Logic App's) matches one of these wildcards. Others are reported as
        skipped.

    .PARAMETER Path
        Write under this folder instead of the repository, at the same
        relative paths, to review an export before it goes in. The
        repository is still what decides which items it already has.

    .PARAMETER Force
        Write over items the repository already has.

    .PARAMETER Format
        The format of a new playbook file: Bicep (the default) or Json. A
        playbook the repository already has is written in its own file's
        format, so a JSON playbook is never shadowed by a new Bicep file.
        Workbooks are not affected.

    .PARAMETER IncludeContentHub
        Export workbooks Content Hub solutions installed. They belong to
        their solution, whose updates would then conflict with the
        repository, so this is almost always wrong.

    .PARAMETER Author
        The author written into exported playbook templates' metadata.

    .PARAMETER Context
        The workspace to export from. Defaults to the one
        Connect-iSOCWorkspace connected.

    .PARAMETER RepoPath
        The repository root. Defaults to the repository the current folder
        is in.

    .OUTPUTS
        [pscustomobject] iSOCDeployments.ExportRun: ContentTypes, Path,
        Results (one iSOCDeployments.ExportResult per workspace item:
        ContentType, Name, Identity, Source, Outcome, Reason, Path,
        Warnings), the counts Created, Updated, Unchanged, Skipped, Failed
        and WhatIf, Warnings (how many items carry warnings), Duration and
        ExitCode (1 when anything failed).

    .EXAMPLE
        Connect-iSOCWorkspace -ResourceGroup rg-sentinel -WorkspaceName law-sentinel -PlaybookResourceGroup rg-automation
        Export-iSOCContent -WhatIf

        Says what exporting every workbook and playbook would write,
        writing nothing.

    .EXAMPLE
        Export-iSOCContent -ContentType Workbook -Name 'Identity*' -Force

        Writes every workbook whose display name starts with Identity,
        over its folder when the repository has it.

    .EXAMPLE
        $run = Export-iSOCContent -ContentType Playbook -Path ./export
        $run.Results | Where-Object Warnings | Format-List Name, Warnings

        Exports playbooks for review outside the repository, and lists
        those holding plain-text secrets.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('iSOCDeployments.ExportRun')]
    param(
        [SupportsWildcards()]
        [string[]] $ContentType,

        [SupportsWildcards()]
        [string[]] $Name,

        [string] $Path,

        [switch] $Force,

        [ValidateSet('Bicep', 'Json')]
        [string] $Format = 'Bicep',

        [switch] $IncludeContentHub,

        [string] $Author = 'noodlemctwoodle',

        [psobject] $Context,

        [string] $RepoPath
    )

    $started = Get-Date
    $ctx = Resolve-iSOCContext -Context $Context
    $repo = Resolve-iSOCRepoPath -RepoPath $RepoPath
    $root = if ($Path) { $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } else { $repo }

    $types = @(Get-iSOCContentTypeDefinition -Name $ContentType)
    if ($ContentType) {
        $cannot = @($types | Where-Object { $_.Capabilities -notcontains 'Export' })
        if ($cannot.Count -gt 0) { throw "The module cannot export $(($cannot | ForEach-Object { $_.Name }) -join ', ') yet." }
    } else {
        $types = @($types | Where-Object { $_.Capabilities -contains 'Export' })
    }
    Assert-iSOCPrerequisite -Step Connect

    $exclude = if ($IncludeContentHub) { @() } else { @('ContentHub') }
    $run = New-iSOCDriftRun -Context $ctx -RepoPath $repo -Options @{ ExcludeSource = $exclude }
    $results = [System.Collections.Generic.List[object]]::new()
    $claimed = @{}

    foreach ($type in $types) {
        $noun = Get-iSOCContentTypeNoun -ContentType $type
        Write-iSOCLog "Exporting $noun" -Level Section
        $items = @(Invoke-iSOCContentTypeHandler -ContentType $type -Handler ReadWorkspace -Parameters @{ Context = $ctx; ContentType = $type })
        foreach ($item in $items) {
            $label = [string](Get-iSOCPropertyValue -InputObject $item -Path 'properties.displayName')
            if (-not $label) { $label = [string](Get-iSOCPropertyValue -InputObject $item -Path 'name') }
            $identity = [string](Get-iSOCPropertyValue -InputObject $item -Path 'name')
            $result = @{ ContentType = $type.Name; Name = $label; Identity = $identity }
            try {
                if ($Name -and -not @($Name | Where-Object { $label -like $_ }).Count) {
                    Write-iSOCLog "Skipping '$label': does not match -Name."
                    $results.Add((New-iSOCExportResult @result -Outcome Skipped -Reason 'not named by -Name'))
                    continue
                }

                $source = Invoke-iSOCContentTypeHandler -ContentType $type -Handler Classify -Parameters @{ Run = $run; ContentType = $type; WorkspaceItem = $item }
                $result.Source = [string]$source.Source
                if ($source.State) {
                    $outcome = if ($source.State -eq 'Failed') { 'Failed' } else { 'Skipped' }
                    $level = if ($outcome -eq 'Failed') { 'Error' } else { 'Info' }
                    Write-iSOCLog "$(if ($outcome -eq 'Failed') { 'Failed to export' } else { 'Skipping' }) '$label': $($source.Reason)." -Level $level
                    $results.Add((New-iSOCExportResult @result -Outcome $outcome -Reason $source.Reason -Path ([string]$source.SourceRef)))
                    continue
                }

                $governed = $source.Source -eq 'Custom'
                if ($governed -and -not $Force) {
                    Write-iSOCLog "Skipping '$label': the repository has it at $($source.SourceRef) (-Force writes over it)."
                    $results.Add((New-iSOCExportResult @result -Outcome Skipped -Reason 'already in the repository (-Force writes over it)' -Path $source.SourceRef))
                    continue
                }

                $relative = if ($governed) { [string]$source.SourceRef } else {
                    [string](Invoke-iSOCContentTypeHandler -ContentType $type -Handler GetRepoPath -Parameters @{ WorkspaceItem = $item; Context = $ctx; Provenance = $source.Source; SolutionName = $source.Solution; Format = $Format })
                }
                if ($claimed.ContainsKey($relative)) {
                    Write-iSOCLog "Skipping '$label': $relative is where '$($claimed[$relative])' was written in this run." -Level Warning
                    $results.Add((New-iSOCExportResult @result -Outcome Skipped -Reason "the same path as '$($claimed[$relative])'" -Path $relative))
                    continue
                }
                if (-not $governed -and (Test-Path -LiteralPath (Join-Path $repo $relative))) {
                    Write-iSOCLog "Skipping '$label': $relative already holds another item." -Level Warning
                    $results.Add((New-iSOCExportResult @result -Outcome Skipped -Reason 'its path already holds another item' -Path $relative))
                    continue
                }
                $claimed[$relative] = $label

                $warnings = [System.Collections.Generic.List[string]]::new()
                $existing = Read-iSOCRepoItemFile -Root $repo -RelativePath $relative -ContentType $type
                $content = Invoke-iSOCContentTypeHandler -ContentType $type -Handler ToRepoFile -Parameters @{
                    WorkspaceItem = $item; Context = $ctx; RelativePath = $relative; Existing = $existing
                    Provenance = $source.Source; SolutionName = $source.Solution; Author = $Author; Warning = $warnings
                }
                $current = if ($root -eq $repo) { $existing } else { Read-iSOCRepoItemFile -Root $root -RelativePath $relative -ContentType $type }
                $change = Get-iSOCRepoItemChange -Existing $current -Content $content
                $result.Warning = $warnings.ToArray()

                if ($change -eq 'Unchanged') {
                    Write-iSOCLog "Unchanged: '$label' ($relative)."
                    $results.Add((New-iSOCExportResult @result -Outcome Unchanged -Path $relative))
                } elseif ($PSCmdlet.ShouldProcess($relative, "Write '$label' from the workspace")) {
                    $action = Save-iSOCRepoItem -Root $root -RelativePath $relative -Content $content
                    Write-iSOCLog "Exported '$label' -> $relative ($($action.ToLowerInvariant()))." -Level Success
                    $results.Add((New-iSOCExportResult @result -Outcome $action -Path $relative))
                } else {
                    $results.Add((New-iSOCExportResult @result -Outcome WhatIf -Reason "would be $($change.ToLowerInvariant())" -Path $relative))
                }
            } catch {
                Write-iSOCLog "Failed to export '$label': $($_.Exception.Message)" -Level Error
                $result.Remove('Warning')
                $results.Add((New-iSOCExportResult @result -Outcome Failed -Reason $_.Exception.Message))
            }
        }
    }

    $count = { param([string] $Outcome) @($results | Where-Object { $_.Outcome -eq $Outcome }).Count }
    $failed = & $count 'Failed'
    $exportRun = [pscustomobject]@{
        PSTypeName   = 'iSOCDeployments.ExportRun'
        ContentTypes = @($types | ForEach-Object { $_.Name })
        Path         = $root
        Results      = $results.ToArray()
        Created      = & $count 'Created'
        Updated      = & $count 'Updated'
        Unchanged    = & $count 'Unchanged'
        Skipped      = & $count 'Skipped'
        Failed       = $failed
        WhatIf       = & $count 'WhatIf'
        Warnings     = @($results | Where-Object { @($_.Warnings).Count -gt 0 }).Count
        Duration     = (Get-Date) - $started
        ExitCode     = [int]($failed -gt 0)
    }
    Write-iSOCExportSummary -Run $exportRun
    $exportRun
}

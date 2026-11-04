#Requires -Version 7.2

<#
.SYNOPSIS
    Import-iSOCCommunityRule: bring a community repository's analytics rules
    into the repository.

.DESCRIPTION
    Replaces Tools/Import-CommunityRules.ps1. Its -DryRun is -WhatIf, its
    settings for David Alonso's repository are the Dalonso source
    (Get-iSOCCommunitySource), and the ids it reserves are the repository's
    -RepoPath rather than the script's own folder (MIGRATION.md edit E28).

.NOTES
    File:         Modules/iSOCDeployments/Public/Import-iSOCCommunityRule.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.0
    Last Updated: 2026-11-04
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter and
    per-example detail lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Import-iSOCCommunityRule {
    <#
    .SYNOPSIS
        Import a community source's analytics rules under
        Content/AnalyticalRules/Community/<Source>/, normalised and
        disabled.

    .DESCRIPTION
        The source repository is cloned shallowly (or -SourcePath read), and
        every rule in the source's folders is read and normalised: set
        disabled, the source's attribution before its description, its tags
        added, a short trigger operator spelt as the API does, and with
        -IncludeKqlConversion the alertRules of the source's ARM templates
        too. A rule that is not valid is skipped with the reason.

        Every rule then gets an id no other rule file in the repository
        uses, keeping the id its file already has, since the deployer names
        each rule in the workspace by its id; a rule whose upstream id is
        taken gets a stable one of its own. Each rule is written to
        <category>/<file> under the output folder unless its file holds that
        text already, with import-manifest.json beside them (the source, its
        commit and each rule's hash) and a README under
        Docs/Content/Community/. When the commit and every rule are as the
        manifest records, the manifest and README keep their date, so an
        import that finds nothing new changes no file. Nothing is deleted.
        With -WhatIf the source is read and nothing written, and each rule
        says what would be.

    .PARAMETER Source
        The community source, as Get-iSOCCommunitySource names it.
        Defaults to Dalonso.

    .PARAMETER SourceRepo
        Clone this repository instead of the source's own.

    .PARAMETER SourceBranch
        Clone this branch instead of the source's own.

    .PARAMETER SourcePath
        Read a checkout already on disk instead of cloning.

    .PARAMETER IncludeKqlConversion
        Import the source's ARM template folders as well.

    .PARAMETER OutputPath
        The folder rules and the manifest go to. Defaults to
        Content/AnalyticalRules/Community/<Source> in the repository.

    .PARAMETER DocsPath
        The README. Defaults to Docs/Content/Community/<folder>.md in the
        repository, named after the output folder.

    .PARAMETER RepoPath
        The repository root. Defaults to the repository the current folder
        is in.

    .OUTPUTS
        [pscustomobject] iSOCDeployments.CommunityImportRun: Source,
        SourceRepo, SourceBranch, SourceCommit, OutputPath, DocsPath,
        Results (one iSOCDeployments.CommunityRuleResult per rule:
        Category, Name, Path, Outcome, Reason, Id, UpstreamId), IdChanges,
        the counts Created, Updated, Unchanged, Skipped and WhatIf,
        Manifest and Readme (Created, Updated, Unchanged or WhatIf),
        Duration and ExitCode.

    .EXAMPLE
        Import-iSOCCommunityRule -WhatIf

        Says what importing David Alonso's rules would change, writing
        nothing.

    .EXAMPLE
        Import-iSOCCommunityRule -IncludeKqlConversion

        Imports the YAML rules and the ARM template rules.

    .EXAMPLE
        Import-iSOCCommunityRule -SourcePath ~/src/Dalonso-Security-Repo

        Imports from a checkout on disk, without cloning.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('iSOCDeployments.CommunityImportRun')]
    param(
        [string] $Source = 'Dalonso',

        [string] $SourceRepo,

        [string] $SourceBranch,

        [string] $SourcePath,

        [switch] $IncludeKqlConversion,

        [string] $OutputPath,

        [string] $DocsPath,

        [string] $RepoPath
    )

    $started = Get-Date
    $definition = Get-iSOCCommunitySource -Name $Source
    $repo = Resolve-iSOCRepoPath -RepoPath $RepoPath
    $repository = if ($SourceRepo) { $SourceRepo } else { $definition.Repository }
    $branch = if ($SourceBranch) { $SourceBranch } else { $definition.Branch }
    $output = if ($OutputPath) { $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath) } else { Join-Path $repo "Content/AnalyticalRules/Community/$($definition.Name)" }
    $docs = if ($DocsPath) { $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DocsPath) } else { Join-Path $repo "Docs/Content/Community/$(Split-Path -Leaf $output).md" }

    $steps = @('Read')
    if (-not $SourcePath) { $steps += 'Import' }
    Assert-iSOCPrerequisite -Step $steps
    Write-iSOCLog "Import Community Rules - $($definition.Name)" -Level Section
    Write-iSOCLog "Output path: $output"
    Import-iSOCYamlModule

    $temp = if ($SourcePath) { $null } else { Join-Path ([System.IO.Path]::GetTempPath()) "community-import-$([System.IO.Path]::GetRandomFileName())" }
    try {
        $checkout = Get-iSOCCommunityCheckout -SourceRepo $repository -SourceBranch $branch -SourcePath $SourcePath -Destination $temp
        $set = Read-iSOCCommunityRuleSet -Path $checkout.Path -Source $definition -SourceRepo $repository -IncludeKqlConversion:$IncludeKqlConversion
        $pending = $set.Pending

        $reserved = Get-iSOCReservedRuleId -RulesRoot (Join-Path $repo 'Content/AnalyticalRules') -ExcludePath $output
        $changes = @(Resolve-iSOCCommunityRuleId -PendingRules $pending -OutputPath $output -SourceRepo $repository -ReservedIds $reserved)
        $changed = @{}
        foreach ($change in $changes) {
            Write-iSOCLog "  ID $($change.RelativePath): $($change.Id) instead of $($change.UpstreamId) ($($change.Reason))" -Level Warning
            $changed[$change.RelativePath] = $change
        }

        Write-iSOCLog 'Writing output files' -Level Section
        $results = [System.Collections.Generic.List[object]]::new()
        $manifestFiles = [ordered]@{}
        $categoryStats = @{}
        $details = @{}
        foreach ($rule in $pending) {
            $category = $rule.Category
            $relative = ([string]$rule.RelativePath).Replace('\', '/')
            if (-not $categoryStats.ContainsKey($category)) {
                $categoryStats[$category] = 0
                $details[$category] = [System.Collections.Generic.List[object]]::new()
            }
            $categoryStats[$category]++

            $text = ([string]$rule.YamlContent).Replace("`r`n", "`n").TrimEnd("`n") + "`n"
            $name = Split-Path -Leaf $relative
            try {
                $parsed = ConvertFrom-Yaml $text -Ordered
                if ($parsed['name']) { $name = [string]$parsed['name'] }
                $details[$category].Add(@{
                        Name        = $name
                        Severity    = $(if ($null -ne $parsed['severity']) { [string]$parsed['severity'] } else { 'Unknown' })
                        Description = $(if ($null -ne $parsed['description']) { [string]$parsed['description'] } else { '' })
                    })
            }
            catch { Write-iSOCLog "  Could not read '$relative' back for the README: $($_.Exception.Message)" -Level Warning }

            $manifestFiles[$relative] = Get-iSOCTextHash -Content $text
            $id = [regex]::Match($text, '(?m)^id:[ \t]*[''"]?([^''"\r\n]+?)[''"]?[ \t]*$').Groups[1].Value
            $upstream = if ($changed.ContainsKey($relative)) { $changed[$relative].UpstreamId } else { '' }
            $result = @{ Category = $category; Name = $name; Path = $relative; Id = $id; UpstreamId = $upstream }

            $target = Join-Path $output $relative
            $existing = if (Test-Path -LiteralPath $target -PathType Leaf) { Get-Content -LiteralPath $target -Raw } else { $null }
            if ($null -ne $existing -and $existing -ceq $text) {
                Write-iSOCLog "  UNCHANGED $relative"
                $results.Add((New-iSOCCommunityResult @result -Outcome Unchanged))
                continue
            }
            $action = if ($null -eq $existing) { 'Created' } else { 'Updated' }
            if ($PSCmdlet.ShouldProcess($relative, "Write community rule '$name'")) {
                Write-iSOCTextFile -Path $target -Content $text
                Write-iSOCLog "  $($action.ToUpperInvariant()) $relative" -Level Success
                $results.Add((New-iSOCCommunityResult @result -Outcome $action))
            }
            else {
                $results.Add((New-iSOCCommunityResult @result -Outcome WhatIf -Reason "would be $($action.ToLowerInvariant())"))
            }
        }
        foreach ($skip in $set.Skipped) {
            $results.Add((New-iSOCCommunityResult -Category $skip.Category -Name $skip.Name -Outcome Skipped -Reason $skip.Reason))
        }

        $manifestPath = Join-Path $output 'import-manifest.json'
        $importDate = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        $previousText = if (Test-Path -LiteralPath $manifestPath -PathType Leaf) { Get-Content -LiteralPath $manifestPath -Raw } else { $null }
        if ($previousText) {
            try {
                $previous = $previousText | ConvertFrom-Json -AsHashtable -Depth 10
                $same = [string]$previous.sourceRepo -ceq $repository -and [string]$previous.sourceBranch -ceq $branch -and [string]$previous.sourceCommitSha -ceq $checkout.Commit -and
                (ConvertTo-Json -InputObject $previous.files -Compress) -ceq (ConvertTo-Json -InputObject $manifestFiles -Compress)
                $date = [regex]::Match($previousText, '"importDate":\s*"([^"]*)"')
                if ($same -and $date.Success) { $importDate = $date.Groups[1].Value }
            }
            catch { Write-iSOCLog "  The existing manifest does not parse; writing a new one: $($_.Exception.Message)" -Level Warning }
        }

        $manifest = [ordered]@{
            sourceRepo      = $repository
            sourceBranch    = $branch
            sourceCommitSha = $checkout.Commit
            importDate      = $importDate
            files           = $manifestFiles
        }
        $readmeDetails = @{}
        foreach ($key in $details.Keys) { $readmeDetails[$key] = @($details[$key]) }
        $readme = ConvertTo-iSOCCommunityReadme -Source $definition -CategoryStats $categoryStats -RuleDetails $readmeDetails -ImportDate $importDate

        $save = {
            param([string] $Path, [string] $Content, [string] $Label)
            $content = $Content.Replace("`r`n", "`n").TrimEnd("`n") + "`n"
            $current = if (Test-Path -LiteralPath $Path -PathType Leaf) { Get-Content -LiteralPath $Path -Raw } else { $null }
            if ($null -ne $current -and $current -ceq $content) { return 'Unchanged' }
            $what = if ($null -eq $current) { 'Created' } else { 'Updated' }
            if (-not $PSCmdlet.ShouldProcess($Path, "Write the $Label")) { return 'WhatIf' }
            Write-iSOCTextFile -Path $Path -Content $content
            Write-iSOCLog "$Label written: $Path" -Level Success
            $what
        }
        $manifestAction = & $save $manifestPath (ConvertTo-Json -InputObject $manifest -Depth 10) 'Manifest'
        $readmeAction = & $save $docs $readme 'README'

        $count = { param([string] $Outcome) @($results | Where-Object { $_.Outcome -eq $Outcome }).Count }
        $run = [pscustomobject]@{
            PSTypeName   = 'iSOCDeployments.CommunityImportRun'
            Source       = $definition.Name
            SourceRepo   = $repository
            SourceBranch = $branch
            SourceCommit = $checkout.Commit
            OutputPath   = $output
            DocsPath     = $docs
            Results      = $results.ToArray()
            IdChanges    = $changes
            Created      = & $count 'Created'
            Updated      = & $count 'Updated'
            Unchanged    = & $count 'Unchanged'
            Skipped      = & $count 'Skipped'
            WhatIf       = & $count 'WhatIf'
            Manifest     = $manifestAction
            Readme       = $readmeAction
            Duration     = (Get-Date) - $started
            ExitCode     = 0
        }
        Write-iSOCCommunityImportSummary -Run $run
        $run
    }
    finally {
        if ($temp -and (Test-Path -LiteralPath $temp)) {
            Remove-Item -LiteralPath $temp -Recurse -Force -WhatIf:$false -Confirm:$false -ErrorAction SilentlyContinue
        }
    }
}

#Requires -Version 7.2

<#
.SYNOPSIS
    Convert-iSOCPlaybook: rewrite the repository's JSON playbooks as Bicep,
    proving each one deploys the same before the JSON goes.

.DESCRIPTION
    New with the move of playbooks to Bicep in 26.11.0 (MIGRATION.md edits
    E47 and E48). Forks run it once to convert their own playbooks; the
    module reads JSON playbooks either way.

.NOTES
    File:         Modules/iSOCDeployments/Public/Convert-iSOCPlaybook.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-06
    Version:      0.1.0
    Last Updated: 2026-11-06
    Requires:     PowerShell 7.2+, the Bicep CLI

    This file defines functions rather than running. Per-parameter and
    per-example detail lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Convert-iSOCPlaybook {
    <#
    .SYNOPSIS
        Convert JSON playbook templates under Content/Playbooks/ to Bicep
        files that deploy the same thing.

    .DESCRIPTION
        For each JSON playbook the Playbook content type reads (so not
        parameter files, bicepconfig.json or the Template folder):

        1. The template is written as Bicep by the module's own writer
           (ConvertTo-iSOCBicepTemplate), into a temporary copy of its
           folder, with the repository's bicepconfig.json beside it.
        2. Every candidate is compiled with the Bicep CLI in one run, and
           each compiled template is compared with its JSON
           (Compare-iSOCArmTemplate: every expression evaluated, key and
           dependsOn order ignored).
        3. Only when the Bicep compiles and deploys the same thing is
           <Name>.bicep written beside the JSON file and the JSON file
           removed. A parameters file beside it stays: it serves the Bicep
           file as it served the JSON.

        A playbook the writer cannot write, that does not compile, or that
        would deploy something else is left as it is and reported with
        why, so nothing is lost. One that already has a .bicep beside it,
        and a file that is not an ARM template, are skipped. With -WhatIf,
        every playbook is still converted and checked in the temporary
        folder, and nothing in the repository changes.

    .PARAMETER Name
        Convert only the playbooks whose name (Category/File, as
        Deploy-iSOCContent names them) or file name matches one of these
        wildcards.

    .PARAMETER RepoPath
        The repository root. Defaults to the repository the current folder
        is in.

    .OUTPUTS
        [pscustomobject] iSOCDeployments.ConvertRun: Results (one
        iSOCDeployments.ConvertResult per JSON playbook, in repository order: Name, Path, Bicep,
        Outcome (Converted, WhatIf, Skipped or Failed), Reason and
        Warnings), the counts Converted, WhatIf, Skipped and Failed,
        Duration and ExitCode (1 when anything failed).

    .EXAMPLE
        Convert-iSOCPlaybook -WhatIf

        Converts and checks every JSON playbook in a temporary folder and
        says what it would do, changing nothing.

    .EXAMPLE
        $run = Convert-iSOCPlaybook
        $run.Results | Where-Object Outcome -eq 'Failed' | Format-List Name, Reason

        Converts every JSON playbook that deploys the same as Bicep, and
        lists the ones left as JSON, with why.

    .EXAMPLE
        Convert-iSOCPlaybook -Name 'Module/*'

        Converts the module playbooks only.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('iSOCDeployments.ConvertRun')]
    param(
        [SupportsWildcards()]
        [string[]] $Name,

        [string] $RepoPath
    )

    $started = Get-Date
    $repo = Resolve-iSOCRepoPath -RepoPath $RepoPath
    Assert-iSOCPrerequisite -Name bicep -Purpose 'converting playbooks to Bicep'
    Write-iSOCLog 'Converting JSON playbooks to Bicep' -Level Section

    $type = Get-iSOCContentTypeDefinition -Name Playbook
    $results = [System.Collections.Generic.List[object]]::new()
    $newResult = {
        param($Item, [string] $Outcome, [string] $Reason, [string[]] $Warnings = @())
        $bicep = [System.IO.Path]::ChangeExtension($Item.RelativePath, '.bicep')
        $results.Add([pscustomobject]@{
                PSTypeName = 'iSOCDeployments.ConvertResult'
                Name       = $Item.Name
                Path       = $Item.RelativePath
                Bicep      = $bicep
                Outcome    = $Outcome
                Reason     = $Reason
                Warnings   = @($Warnings)
            })
    }

    # The temporary copy is written straight through .NET, not with
    # Write-iSOCTextFile, whose New-Item would honour -WhatIf: the check
    # runs under -WhatIf too, and the copy is not the repository.
    $writeStaged = {
        param([string] $Path, [string] $Text)
        [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
        [System.IO.File]::WriteAllText($Path, $Text, [System.Text.UTF8Encoding]::new($false))
    }

    $candidates = [System.Collections.Generic.List[object]]::new()
    $stage = Join-Path ([System.IO.Path]::GetTempPath()) "isoc-convert-$([guid]::NewGuid().ToString('N'))"
    try {
        foreach ($item in @(Invoke-iSOCContentTypeHandler -ContentType $type -Handler ReadRepo -Parameters @{ RepoPath = $repo; ContentType = $type })) {
            if ($item.Format -ne 'Json') { continue }
            if ($Name -and -not @($Name | Where-Object { $item.Name -like $_ -or $item.BaseName -like $_ }).Count) { continue }
            if ($item.ParseError) { & $newResult $item 'Failed' $item.ParseError; continue }
            if (Test-iSOCPlaybook -Item $item) { & $newResult $item 'Skipped' 'not an ARM deployment template'; continue }
            $target = [System.IO.Path]::ChangeExtension($item.Path, '.bicep')
            if (Test-Path -LiteralPath $target) { & $newResult $item 'Skipped' "already has $(Split-Path -Leaf $target) beside it"; continue }

            try {
                $template = ConvertFrom-iSOCJsonText -Text ([System.IO.File]::ReadAllText($item.Path))
                $text = ConvertTo-iSOCBicepTemplate -Template $template
            }
            catch {
                & $newResult $item 'Failed' "cannot be written as Bicep: $($_.Exception.Message)"
                continue
            }
            $staged = Join-Path $stage ([System.IO.Path]::ChangeExtension($item.RelativePath, '.bicep'))
            & $writeStaged $staged $text
            $candidates.Add([pscustomobject]@{ Item = $item; Template = $template; Text = $text; Staged = $staged; Target = $target })
        }

        if ($candidates.Count -gt 0) {
            # The repository's bicepconfig.json files go into the copy at
            # the same places, so the warnings are the ones an editor shows.
            foreach ($folder in @($candidates | ForEach-Object { Split-Path -Parent $_.Item.Path } | Sort-Object -Unique)) {
                $current = $folder
                while ($current -and $current.StartsWith($repo, [System.StringComparison]::Ordinal)) {
                    $config = Join-Path $current 'bicepconfig.json'
                    if (Test-Path -LiteralPath $config -PathType Leaf) {
                        $copy = Join-Path $stage ([System.IO.Path]::GetRelativePath($repo, $config))
                        if (-not (Test-Path -LiteralPath $copy)) { & $writeStaged $copy ([System.IO.File]::ReadAllText($config)) }
                    }
                    if ($current -eq $repo) { break }
                    $current = Split-Path -Parent $current
                }
            }

            $builds = @(Invoke-iSOCBicep -Path @($candidates | ForEach-Object { $_.Staged }))
            for ($i = 0; $i -lt $candidates.Count; $i++) {
                $candidate = $candidates[$i]
                $build = $builds[$i]
                $warnings = @($build.Warnings | ForEach-Object { ($_ -replace '^.*?\(\d+,\d+\) : ', '') })
                if (-not $build.Succeeded) {
                    & $newResult $candidate.Item 'Failed' "the Bicep does not compile: $(@($build.Errors | ForEach-Object { $_ -replace '^.*?\(\d+,\d+\) : ', '' }) -join ' ')" $warnings
                    continue
                }
                $difference = Compare-iSOCArmTemplate -Expected $candidate.Template -Actual $build.Template
                if ($difference) {
                    & $newResult $candidate.Item 'Failed' "the Bicep would deploy something else: $difference" $warnings
                    continue
                }
                $bicepName = Split-Path -Leaf $candidate.Target
                if ($PSCmdlet.ShouldProcess($candidate.Item.RelativePath, "Convert to Bicep: write $bicepName and remove the JSON")) {
                    Write-iSOCTextFile -Path $candidate.Target -Content $candidate.Text
                    Remove-Item -LiteralPath $candidate.Item.Path -Force -WhatIf:$false -Confirm:$false
                    & $newResult $candidate.Item 'Converted' '' $warnings
                }
                else {
                    & $newResult $candidate.Item 'WhatIf' "would write $bicepName and remove the JSON" $warnings
                }
            }
        }
    }
    finally {
        if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force -WhatIf:$false -Confirm:$false }
    }

    $results.Sort([System.Comparison[object]] { param($a, $b) [string]::CompareOrdinal($a.Path, $b.Path) })
    $count = { param([string] $Outcome) @($results | Where-Object { $_.Outcome -eq $Outcome }).Count }
    foreach ($result in $results) {
        $level = switch ($result.Outcome) { 'Failed' { 'Warning' } 'Skipped' { 'Debug' } default { 'Info' } }
        $line = "  $($result.Outcome): $($result.Path)"
        if ($result.Reason) { $line += " ($($result.Reason))" }
        Write-iSOCLog $line -Level $level
    }
    $run = [pscustomobject]@{
        PSTypeName = 'iSOCDeployments.ConvertRun'
        Results    = $results.ToArray()
        Converted  = & $count 'Converted'
        WhatIf     = & $count 'WhatIf'
        Skipped    = & $count 'Skipped'
        Failed     = & $count 'Failed'
        Duration   = (Get-Date) - $started
        ExitCode   = if ((& $count 'Failed') -gt 0) { 1 } else { 0 }
    }
    Write-iSOCLog "Converted $($run.Converted), would convert $($run.WhatIf), skipped $($run.Skipped), failed $($run.Failed)." -Level Info
    $run
}

#Requires -Version 7.6

<#
.SYNOPSIS
    Export-iSOCDriftReport: write a drift report the drift bot commits.

.DESCRIPTION
    The report half of Tools/Test-SentinelRuleDrift.ps1, writing the same
    sentinel-drift-<UTC>.json and .md files under reports/, which the drift
    pipelines look for (MIGRATION.md edit E24).

.NOTES
    File:         Modules/iSOCDeployments/Public/Export-iSOCDriftReport.ps1
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

function Export-iSOCDriftReport {
    <#
    .SYNOPSIS
        Write a compare's result as a JSON and a Markdown report, when
        anything drifted.

    .DESCRIPTION
        The files are sentinel-drift-<yyyy-MM-ddTHH-mmZ>.json and .md, named
        by the UTC time so two runs never write the same file. The JSON
        holds the summary, every drifted rule with its changed fields in
        full, and every orphan; the Markdown is the same for a pull request,
        with a diff of each changed query. After Sync-iSOCContent they say
        which files were written. Paths in them are repository-relative, and
        no subscription id is written. When nothing drifted no file is
        written, so the drift pipeline has nothing to commit. With -WhatIf
        nothing is written.

    .PARAMETER InputObject
        A Compare-iSOCContent result, after Sync-iSOCContent when it ran.

    .PARAMETER Path
        The folder to write to. Defaults to reports/ in the repository the
        compare read.

    .OUTPUTS
        [System.IO.FileInfo] The two files written; nothing when nothing
        drifted.

    .EXAMPLE
        Compare-iSOCContent | Sync-iSOCContent | Export-iSOCDriftReport

        Finds the drift, writes it into the repository, and writes the
        report.

    .EXAMPLE
        Compare-iSOCContent -Severity High | Export-iSOCDriftReport -Path ~/drift

        Reports high-severity drift to a folder outside the repository,
        changing no rule file.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [psobject] $InputObject,

        [string] $Path
    )

    process {
        if (-not $InputObject.HasDrift) {
            Write-iSOCLog 'No drift detected; skipping report write to keep working tree clean.'
            return
        }

        $folder = if ($Path) { $Path } else { Join-Path $InputObject.RepoPath 'reports' }
        $stamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH-mmZ')
        $report = ConvertTo-iSOCDriftReport -Drift $InputObject
        $files = @(
            @{ Name = "sentinel-drift-$stamp.json"; Text = (ConvertTo-Json -InputObject $report -Depth 8) + "`n"; Label = 'drift report' }
            @{ Name = "sentinel-drift-$stamp.md"; Text = (ConvertTo-iSOCDriftMarkdown -Report $report) + "`n"; Label = 'markdown report' }
        )

        if (-not $PSCmdlet.ShouldProcess($folder, "Write $($files[0].Name) and $($files[1].Name)")) { return }
        if (-not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
        foreach ($file in $files) {
            $target = Join-Path $folder $file.Name
            [System.IO.File]::WriteAllText($target, $file.Text, [System.Text.UTF8Encoding]::new($false))
            Write-iSOCLog "Wrote $($file.Label): $target" -Level Success
            Get-Item -LiteralPath $target
        }
    }
}

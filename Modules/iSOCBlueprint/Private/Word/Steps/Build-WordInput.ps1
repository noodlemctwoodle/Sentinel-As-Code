#Requires -Version 7.6

<#
.SYNOPSIS
    Write cleaned copies of the Markdown for pandoc: provenance line stripped, findings and status words styled.

.DESCRIPTION
    A step of the Word report conversion. Steps run in order and pass their results
    to later ones through the conversion context.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Word/Steps/Build-WordInput.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, Word report
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Build-WordInput {
    <#
    .SYNOPSIS
        Write cleaned copies of the Markdown for pandoc: provenance line stripped, findings and status words styled.

    .PARAMETER Context
        The conversion context: the values earlier steps produced and this one adds to.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the conversion context.
    $mdPaths = $Context.mdPaths
    $NoReformatFindings = $Context.NoReformatFindings
    $OutputPath = $Context.OutputPath
    $StripLinePattern = $Context.StripLinePattern

    # ---------------------------------------------------------------------------
    # Run pandoc
    # ---------------------------------------------------------------------------

    if (-not $PSCmdlet.ShouldProcess($OutputPath, 'Write Word document via pandoc')) {
        $Context.stop = $true
        return
    }

    # Preprocess: strip the repeated provenance line from each file. Cleaned
    # copies go to a temp dir; images still resolve because --resource-path
    # points at the original folder, not these temp files.
    # Pass 1: collect finding titles across every file, so dense bullets can
    # be split into title + description reliably.
    $titleMap = @{}
    if (-not $NoReformatFindings) {
        $allText = foreach ($p in $mdPaths) { Get-Content -LiteralPath $p -Raw }
        $titleMap = Get-FindingTitleMap -Texts @($allText)
    }

    # Pass 2: strip the provenance line, reformat finding bullets, write a
    # cleaned copy to the temp dir.
    $work = Join-Path ([System.IO.Path]::GetTempPath()) ('md2word-{0}' -f ([guid]::NewGuid().ToString('N')))
    [void](New-Item -ItemType Directory -Path $work -Force)
    $inputPaths = [System.Collections.Generic.List[string]]::new()
    $stripped = 0
    $reformatted = 0
    $recoloured = 0
    $idx = 0
    foreach ($p in $mdPaths) {
        $idx++
        $text = Get-Content -LiteralPath $p -Raw
        if ($null -eq $text) { $text = '' }
        # Keep the provenance line in the first (overview) section so it
        # appears once under its heading; strip the repeats from later files.
        if ($StripLinePattern -and $idx -gt 1) {
            $cleaned = [regex]::Replace($text, $StripLinePattern, '')
            if ($cleaned -ne $text) { $stripped++; $text = $cleaned }
        }
        if (-not $NoReformatFindings) {
            $cnt = [ref]0
            $text = Convert-FindingBullet -Text $text -TitleMap $titleMap -Count $cnt
            $reformatted += $cnt.Value

            $ecnt = [ref]0
            $text = Convert-StatusWord -Text $text -Count $ecnt
            $recoloured += $ecnt.Value
        }
        $dest = Join-Path $work ('{0:D4}-{1}' -f $idx, (Split-Path $p -Leaf))
        Set-Content -LiteralPath $dest -Value $text -Encoding utf8
        $inputPaths.Add($dest)
    }

    # Left in the conversion context for later steps.
    $Context.inputPaths = $inputPaths
    $Context.recoloured = $recoloured
    $Context.reformatted = $reformatted
    $Context.stripped = $stripped
    $Context.work = $work
}

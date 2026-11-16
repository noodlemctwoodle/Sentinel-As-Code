#Requires -Version 7.6

<#
.SYNOPSIS
    Report what the conversion changed and where the document is.

.DESCRIPTION
    A step of the Word report conversion. Steps run in order and pass their results
    to later ones through the conversion context.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Word/Steps/Write-WordSummary.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-16
    Component:    iSOC Blueprint, Word report
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Write-WordSummary {
    <#
    .SYNOPSIS
        Report what the conversion changed and where the document is.

    .PARAMETER Context
        The conversion context: the values earlier steps produced and this one adds to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [hashtable] $Context)

    # Taken from the conversion context.
    $exit = $Context.exit
    $NoReformatFindings = $Context.NoReformatFindings
    $OutputPath = $Context.OutputPath
    $pandocOut = $Context.pandocOut
    $recoloured = $Context.recoloured
    $reformatted = $Context.reformatted
    $StripLinePattern = $Context.StripLinePattern
    $stripped = $Context.stripped

    # Surface missing-image warnings (pandoc leaves the alt text in place).
    $missing = @($pandocOut | Select-String -Pattern 'Could not fetch resource')
    foreach ($line in ($pandocOut | Where-Object { $_ -notmatch 'Could not fetch resource' })) {
        if ("$line".Trim()) { Write-WordLog "  pandoc: $line" -Level Info }
    }

    if ($exit -ne 0) {
        foreach ($line in $pandocOut) { Write-WordLog "  $line" -Level Error }
        throw "pandoc failed (exit $exit)."
    }

    # ---------------------------------------------------------------------------
    # Summary
    # ---------------------------------------------------------------------------

    Write-WordLog 'Summary' -Level Section
    if ($StripLinePattern -and $stripped -gt 0) {
        Write-WordLog "  Provenance line stripped from $stripped file(s)."
    }
    if (-not $NoReformatFindings -and $reformatted -gt 0) {
        Write-WordLog "  Reformatted $reformatted finding bullet(s)."
    }
    if (-not $NoReformatFindings -and $recoloured -gt 0) {
        Write-WordLog "  Recoloured $recoloured severity label(s)."
    }
    if ($missing.Count -gt 0) {
        Write-WordLog "  $($missing.Count) image(s) not found on disk - left as alt text (broken links in the source)." -Level Warning
    }
    else {
        Write-WordLog "  All images resolved." -Level Info
    }

    if (Test-Path -LiteralPath $OutputPath) {
        $sizeKb = [math]::Round((Get-Item -LiteralPath $OutputPath).Length / 1KB, 1)
        Write-WordLog "  Output: $OutputPath ($sizeKb KB)" -Level Success
    }
}

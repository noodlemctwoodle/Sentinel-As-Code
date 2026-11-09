#Requires -Version 7.6

<#
.SYNOPSIS
    Compile Bicep files with the Bicep CLI.

.DESCRIPTION
    The only place the module runs the Bicep CLI (Module.Tests.ps1), so a
    test can stand it in. The CLI must be on the PATH (the bicep row of
    Get-iSOCRequirement); the module never installs it.

.NOTES
    File:         Modules/iSOCDeployments/Private/Bicep/Invoke-iSOCBicep.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-06
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+, the Bicep CLI

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Invoke-iSOCBicep {
    <#
    .SYNOPSIS
        Build .bicep files to their ARM templates, all in one run of the
        CLI.

    .DESCRIPTION
        Starting the CLI costs about a second, and building a playbook a few
        milliseconds, so the files are built together: bicep build --pattern
        '<folder>/**/*.bicep' --outdir <temporary folder>, where <folder> is
        the deepest folder that holds every file. The files are read where
        they are, so the bicepconfig.json above them and anything they load
        resolve as they would in an editor. Only the compiled templates are
        written, to the temporary folder, which is removed afterwards, so
        nothing lands beside the sources. Other .bicep files under <folder>
        are built too and ignored.

        Each compiled template is returned as text and parsed with
        ConvertFrom-iSOCJsonText, so dates stay as written. The CLI's
        diagnostics are given to the file they name, split into errors and
        warnings (the notice that a newer Bicep is out is dropped). It never
        throws for a file that does not compile; the caller decides what an
        error means.

    .PARAMETER Path
        The .bicep files.

    .OUTPUTS
        [pscustomobject] One per file, in the order given: Path, Succeeded,
        Json (the compiled template's text, or null), Template (the parsed
        template, or null), Errors and Warnings (the diagnostic lines).

    .EXAMPLE
        $builds = Invoke-iSOCBicep -Path $files.FullName
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Path
    )

    $files = @($Path | Where-Object { $_ } | ForEach-Object { [System.IO.Path]::GetFullPath($_) })
    if ($files.Count -eq 0) { return }

    $root = [System.IO.Path]::GetDirectoryName($files[0])
    foreach ($file in $files) {
        $folder = [System.IO.Path]::GetDirectoryName($file)
        while (-not ($folder + [System.IO.Path]::DirectorySeparatorChar).StartsWith($root + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::Ordinal)) {
            $root = [System.IO.Path]::GetDirectoryName($root)
        }
    }

    $out = Join-Path ([System.IO.Path]::GetTempPath()) "isoc-bicep-$([guid]::NewGuid().ToString('N'))"
    [void][System.IO.Directory]::CreateDirectory($out)
    try {
        $pattern = ($root.Replace('\', '/').TrimEnd('/')) + '/**/*.bicep'
        # Quoted: on macOS and Linux PowerShell expands wildcards in a bare
        # native argument, which would hand Bicep a list of files.
        $output = & bicep build --pattern "$pattern" --outdir "$out" 2>&1
        $code = $LASTEXITCODE
        $diagnostics = @($output | ForEach-Object { "$_" } | Where-Object { $_ -and $_ -notmatch 'new Bicep release is available' })

        foreach ($file in $files) {
            $relative = [System.IO.Path]::GetRelativePath($root, $file)
            $compiled = Join-Path $out ([System.IO.Path]::ChangeExtension($relative, '.json'))
            $mine = @($diagnostics | Where-Object { $_.StartsWith("$file(", [System.StringComparison]::OrdinalIgnoreCase) })
            $errors = @($mine | Where-Object { $_ -match ' : Error ' })
            $json = if (Test-Path -LiteralPath $compiled -PathType Leaf) { [System.IO.File]::ReadAllText($compiled) } else { $null }
            if (-not $json -and $errors.Count -eq 0) {
                $errors = @("bicep build exited with code $code and wrote no template. $(@($diagnostics | Where-Object { $_ -notmatch ' : Warning ' }) -join ' ')")
            }
            [pscustomobject]@{
                Path      = $file
                Succeeded = [bool]$json -and $errors.Count -eq 0
                Json      = $json
                Template  = if ($json) { ConvertFrom-iSOCJsonText -Text $json } else { $null }
                Errors    = $errors
                Warnings  = @($mine | Where-Object { $_ -match ' : Warning ' })
            }
        }
    }
    finally {
        Remove-Item -LiteralPath $out -Recurse -Force -ErrorAction SilentlyContinue -WhatIf:$false -Confirm:$false
    }
}

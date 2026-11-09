#Requires -Version 7.6

<#
.SYNOPSIS
    The fields where a workspace item differs from what the repository
    would send.

.DESCRIPTION
    Replaces Compare-SentinelRule (Tools/Test-SentinelRuleDrift.ps1): the
    fields compared, and how, are the content type's Fields, so every type
    is compared the same way (MIGRATION.md edit E22).

.NOTES
    File:         Modules/iSOCDeployments/Private/Drift/Compare-iSOCContentBody.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Compare-iSOCContentBody {
    <#
    .SYNOPSIS
        Compare two request bodies field by field and return each
        difference.

    .DESCRIPTION
        For each of the content type's Fields, in order: a field with a Kind
        is compared only when the workspace item is of that kind (a
        Scheduled rule's schedule, say, which an NRT rule has none of); a
        field the repository leaves unset ($null) is not compared, since the
        repository does not decide it; otherwise the two values are compared
        with the field's comparer (Compare-iSOCFieldValue). The values are
        returned as each side has them, not normalised, so they can be
        written back and shown in full.

    .PARAMETER ContentType
        The content type.

    .PARAMETER Expected
        The body the repository would send (the ToRequest body, or a
        template's).

    .PARAMETER Actual
        The workspace item in the same shape (from ToComparable).

    .OUTPUTS
        [pscustomobject] One per differing field: Field (its name without
        the properties. prefix), Path (its place in the body), Deployed and
        Expected.

    .EXAMPLE
        $modifications = @(Compare-iSOCContentBody -ContentType $rules -Expected $request.Body -Actual $actual)
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [psobject] $ContentType,

        [Parameter(Mandatory)]
        [object] $Expected,

        [Parameter(Mandatory)]
        [object] $Actual
    )

    $actualKind = [string](Get-iSOCPropertyValue -InputObject $Actual -Path 'kind')
    foreach ($field in @($ContentType.Fields)) {
        if ($field.ContainsKey('Kind') -and $field.Kind -and $actualKind -ne $field.Kind) { continue }
        $expectedValue = Get-iSOCPropertyValue -InputObject $Expected -Path $field.Name
        if ($null -eq $expectedValue) { continue }
        $actualValue = Get-iSOCPropertyValue -InputObject $Actual -Path $field.Name
        if (-not (Compare-iSOCFieldValue -Comparer $field.Comparer -Expected $expectedValue -Actual $actualValue)) {
            [pscustomobject]@{
                Field    = $field.Name -replace '^properties\.', ''
                Path     = $field.Name
                Deployed = $actualValue
                Expected = $expectedValue
            }
        }
    }
}

#Requires -Version 7.6

<#
.SYNOPSIS
    Flatten an ARM error, with its nested details, into one line.

.DESCRIPTION
    A preflight failure says only "See inner errors for details"; the reason
    is one or more levels down.

.NOTES
    File:         Modules/iSOCDeployments/Private/Deploy/Format-iSOCDeploymentError.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Format-iSOCDeploymentError {
    <#
    .SYNOPSIS
        Flatten an ARM error, with its nested details, into one line.

    .DESCRIPTION
        Each level reads [Code] (Target) Message, in either casing, and its
        Details, InnerError or AdditionalInfo are followed, joined by ' -> ',
        to six levels. A string is returned as it is. A collection (as
        Test-AzResourceGroupDeployment returns its errors, handed over as one
        object) is formatted item by item and joined by ' | '. An error
        whose shape is not recognised is never returned empty: it is
        written out as JSON, named as an unrecognised shape.

    .PARAMETER ErrorObject
        The error.

    .PARAMETER Depth
        How far down this call is; 0 unless given.

    .OUTPUTS
        [string]

    .EXAMPLE
        Format-iSOCDeploymentError -ErrorObject $validationError
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object] $ErrorObject,

        [int] $Depth = 0
    )

    if ($null -eq $ErrorObject -or $Depth -gt 6) { return '' }
    if ($ErrorObject -is [string]) { return $ErrorObject }

    if ($ErrorObject -is [System.Collections.IEnumerable] -and $ErrorObject -isnot [System.Collections.IDictionary]) {
        $items = @(@($ErrorObject | ForEach-Object { Format-iSOCDeploymentError -ErrorObject $_ -Depth $Depth }) | Where-Object { $_ })
        if ($items.Count -gt 0) { return ($items -join ' | ') }
    }

    $parts = [System.Collections.Generic.List[string]]::new()
    $code = $ErrorObject.PSObject.Properties['Code']
    $message = $ErrorObject.PSObject.Properties['Message']
    $target = $ErrorObject.PSObject.Properties['Target']

    $label = @()
    if ($code -and $code.Value) { $label += "[$($code.Value)]" }
    if ($target -and $target.Value) { $label += "($($target.Value))" }
    if ($message -and $message.Value) { $label += [string]$message.Value }
    if ($label.Count -gt 0) { $parts.Add(($label -join ' ')) }

    foreach ($name in @('Details', 'details', 'InnerError', 'AdditionalInfo')) {
        $collection = $ErrorObject.PSObject.Properties[$name]
        if (-not $collection -or -not $collection.Value) { continue }
        foreach ($inner in @($collection.Value)) {
            $nested = Format-iSOCDeploymentError -ErrorObject $inner -Depth ($Depth + 1)
            if ($nested) { $parts.Add($nested) }
        }
        break
    }

    $flattened = ($parts | Where-Object { $_ }) -join ' -> '

    if (-not $flattened -and $Depth -eq 0) {
        $flattened = try { $ErrorObject | ConvertTo-Json -Depth 10 -Compress }
        catch { ($ErrorObject | Out-String).Trim() }
        if ($flattened) {
            $flattened = "unrecognised error shape ($($ErrorObject.GetType().Name)): $flattened"
        }
    }
    $flattened
}

#Requires -Version 7.6

<#
.SYNOPSIS
    Decide whether a field holds the same value in the repository and the
    workspace.

.NOTES
    File:         Modules/iSOCDeployments/Private/Drift/Compare-iSOCFieldValue.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-23
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    The comparer names in the ValidateSet below are the ones a content type's
    field list may use; Test-iSOCContentTypeDefinition reads them from here.
#>

# Keeps the file help above from being read as the help of the function below.

function Compare-iSOCFieldValue {
    <#
    .SYNOPSIS
        Compare two values the way a content type's field list says to.

    .DESCRIPTION
        Comparers:

          Exact            same text, case-sensitive
          CaseInsensitive  same text, ignoring case
          Whitespace       same text once runs of whitespace are one space
                           and the ends are trimmed, case-sensitive (KQL is)
          Number           the same number (5 and 5.0 are equal)
          Duration         the same ISO 8601 duration (PT24H and P1D are equal)
          Set              the same members, in any order, duplicates ignored
          OrderedList      the same members in the same order
          Json             the same structure, keys in any order
          Ignore           always equal

        A missing value, an empty string, an empty list and an empty mapping
        all mean "not set" and are equal to each other.

    .PARAMETER Comparer
        One of the comparers above.

    .PARAMETER Expected
        The value the repository gives.

    .PARAMETER Actual
        The value the workspace holds.

    .OUTPUTS
        [bool] $true when the values are equal.

    .EXAMPLE
        Compare-iSOCFieldValue -Comparer Duration -Expected 'PT24H' -Actual 'P1D'

        Returns $true.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Exact', 'CaseInsensitive', 'Whitespace', 'Number', 'Duration', 'Set', 'OrderedList', 'Json', 'Ignore')]
        [string] $Comparer,

        [AllowNull()]
        [object] $Expected,

        [AllowNull()]
        [object] $Actual
    )

    if ($Comparer -eq 'Ignore') { return $true }

    $isUnset = {
        param($Value)
        if ($null -eq $Value) { return $true }
        if ($Value -is [string]) { return ($Value.Length -eq 0) }
        if ($Value -is [System.Collections.IDictionary]) { return ($Value.Count -eq 0) }
        if ($Value -is [System.Collections.IEnumerable]) { return (@($Value).Count -eq 0) }
        if ($Value -is [System.Management.Automation.PSCustomObject]) { return (@($Value.PSObject.Properties).Count -eq 0) }
        $false
    }
    $expectedUnset = & $isUnset $Expected
    $actualUnset = & $isUnset $Actual
    if ($expectedUnset -or $actualUnset) { return ($expectedUnset -and $actualUnset) }

    $text = {
        param($Value)
        if ($Value -is [System.IFormattable]) { return $Value.ToString($null, [System.Globalization.CultureInfo]::InvariantCulture) }
        [string]$Value
    }

    switch ($Comparer) {
        'Exact' {
            return [string]::Equals((& $text $Expected), (& $text $Actual), [System.StringComparison]::Ordinal)
        }
        'CaseInsensitive' {
            return [string]::Equals((& $text $Expected), (& $text $Actual), [System.StringComparison]::OrdinalIgnoreCase)
        }
        'Whitespace' {
            $e = ((& $text $Expected) -replace '\s+', ' ').Trim()
            $a = ((& $text $Actual) -replace '\s+', ' ').Trim()
            return [string]::Equals($e, $a, [System.StringComparison]::Ordinal)
        }
        'Number' {
            $style = [System.Globalization.NumberStyles]::Float
            $culture = [System.Globalization.CultureInfo]::InvariantCulture
            $e = [decimal]0
            $a = [decimal]0
            if ([decimal]::TryParse((& $text $Expected), $style, $culture, [ref]$e) -and [decimal]::TryParse((& $text $Actual), $style, $culture, [ref]$a)) {
                return ($e -eq $a)
            }
            return [string]::Equals((& $text $Expected), (& $text $Actual), [System.StringComparison]::Ordinal)
        }
        'Duration' {
            return [string]::Equals((ConvertTo-iSOCCanonicalDuration (& $text $Expected)), (ConvertTo-iSOCCanonicalDuration (& $text $Actual)), [System.StringComparison]::Ordinal)
        }
        'Set' {
            $toSet = {
                param($Value)
                $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
                foreach ($member in @($Value)) {
                    if ($null -ne $member) { [void]$set.Add((& $text $member)) }
                }
                , $set
            }
            return (& $toSet $Expected).SetEquals((& $toSet $Actual))
        }
        default {
            # OrderedList and Json: the same structure once keys are sorted.
            return [string]::Equals((ConvertTo-iSOCCanonicalJson $Expected), (ConvertTo-iSOCCanonicalJson $Actual), [System.StringComparison]::Ordinal)
        }
    }
}

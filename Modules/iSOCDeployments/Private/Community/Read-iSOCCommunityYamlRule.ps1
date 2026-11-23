#Requires -Version 7.6

<#
.SYNOPSIS
    Read one community YAML rule file and normalise it.

.DESCRIPTION
    Copied from Import-YamlFile (Tools/Import-CommunityRules.ps1).

.NOTES
    File:         Modules/iSOCDeployments/Private/Community/Read-iSOCCommunityYamlRule.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

    Needs powershell-yaml when it runs. Import-iSOCYamlModule loads it
    then instead of #Requires, so the module imports without it.
#>

# Keeps the file help above from being read as the help of the function below.

function Read-iSOCCommunityYamlRule {
    <#
    .SYNOPSIS
        Return a source rule file's normalised YAML, or why it was left out.

    .DESCRIPTION
        The file is parsed in order, so the rule keeps its key order. A file
        that does not parse, is not a mapping, or fails
        ConvertTo-iSOCCommunityRuleYaml's checks is warned about and comes
        back with an Error instead.

    .PARAMETER Path
        The rule file.

    .PARAMETER Source
        The community source.

    .OUTPUTS
        [pscustomobject] YamlContent, or Error.

    .EXAMPLE
        $rule = Read-iSOCCommunityYamlRule -Path $file.FullName -Source $source
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [hashtable] $Source
    )

    try {
        Import-iSOCYamlModule
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding utf8
        $rule = ConvertFrom-Yaml $raw -Ordered
        if ($null -eq $rule -or $rule -isnot [System.Collections.IDictionary]) { throw 'the YAML is not a mapping' }
        [pscustomobject]@{ YamlContent = (ConvertTo-iSOCCommunityRuleYaml -Rule $rule -SourceFile $Path -Source $Source); Error = $null }
    } catch {
        Write-iSOCLog "Skipping '$Path': $($_.Exception.Message)" -Level Warning
        [pscustomobject]@{ YamlContent = $null; Error = $_.Exception.Message }
    }
}

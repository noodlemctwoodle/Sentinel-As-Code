#Requires -Version 7.6

<#
.SYNOPSIS
    The Sentinel entity types a workflow works on.

.DESCRIPTION
    Copied from Get-WorkflowEntities (847ef86:Tools/Export-Playbooks.ps1).

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/Playbook/Get-iSOCPlaybookEntity.ps1
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

function Get-iSOCPlaybookEntity {
    <#
    .SYNOPSIS
        Return the entity types a workflow definition names, sorted.

    .DESCRIPTION
        Reads entity trigger paths (/entity/{type}), entity action paths
        (/entities/{type}) and the portal's default action names
        (Entities_-_Get_IPs and the like), and maps each to its Sentinel
        entity type: the word as it is, then without a plural 'es', then
        without a plural 's', so DNS stays DNS while FileHashes and IPs
        become FileHash and IP.

    .PARAMETER Definition
        The workflow definition.

    .OUTPUTS
        [string] One entity type each.

    .EXAMPLE
        Get-iSOCPlaybookEntity -Definition $app.properties.definition
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [object] $Definition
    )

    $entityMap = @{
        'ip'       = 'IP'
        'host'     = 'Host'
        'account'  = 'Account'
        'filehash' = 'FileHash'
        'url'      = 'URL'
        'file'     = 'File'
        'dns'      = 'DNS'
        'process'  = 'Process'
        'malware'  = 'Malware'
        'registry' = 'RegistryKey'
    }

    $json = $Definition | ConvertTo-Json -Depth 100 -Compress
    $candidates = [System.Collections.Generic.List[string]]::new()
    foreach ($m in [regex]::Matches($json, "/entit(?:y|ies)/(?:@\{encodeURIComponent\(')?([A-Za-z]+)")) { $candidates.Add($m.Groups[1].Value) }
    foreach ($m in [regex]::Matches($json, 'Entities_-_Get_([A-Za-z]+)')) { $candidates.Add($m.Groups[1].Value) }

    $found = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($raw in $candidates) {
        $key = $raw.ToLowerInvariant()
        $match = @($key, ($key -replace 'es$', ''), ($key -replace 's$', '')) |
            Where-Object { $entityMap.ContainsKey($_) } |
            Select-Object -First 1
        if ($match) { [void]$found.Add($entityMap[$match]) }
    }
    @($found | Sort-Object)
}

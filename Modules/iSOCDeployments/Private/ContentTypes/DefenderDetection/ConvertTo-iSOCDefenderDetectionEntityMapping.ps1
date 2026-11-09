#Requires -Version 7.6

<#
.SYNOPSIS
    Build alertTemplate.entityMappings from retired impactedAssets.

.DESCRIPTION
    Copied from ConvertTo-DetectionEntityMapping
    (Deploy/content/Deploy-DefenderDetections.ps1).

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/DefenderDetection/ConvertTo-iSOCDefenderDetectionEntityMapping.ps1
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

function ConvertTo-iSOCDefenderDetectionEntityMapping {
    <#
    .SYNOPSIS
        Return the entity mappings, one per impacted asset.

    .DESCRIPTION
        Each impacted asset becomes one mapping in the matching collection
        (accounts, hosts, mailboxes). Its identifier token names the query
        column, and the token's suffix picks the column property: ObjectId
        maps to aadUserIdColumn, Sid to sidColumn, Upn to upnColumn, Name to
        nameColumn, Domain to ntDomainColumn, a device Id to deviceIdColumn,
        and a mailbox Address to primaryAddressColumn. A token that fits none
        of these throws, so nothing is guessed.

    .PARAMETER ImpactedAssets
        The retired alertTemplate.impactedAssets.

    .OUTPUTS
        [System.Collections.Specialized.OrderedDictionary] Collection name to
        its list of mappings.

    .EXAMPLE
        ConvertTo-iSOCDefenderDetectionEntityMapping -ImpactedAssets $template['impactedAssets']
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [AllowNull()]
        [object[]] $ImpactedAssets
    )

    $mappings = [ordered]@{}
    foreach ($asset in @($ImpactedAssets)) {
        if ($null -eq $asset) { continue }
        $type = ([string]$asset['@odata.type']) -replace '^#?microsoft\.graph\.security\.', ''
        $identifier = [string]$asset['identifier']
        $column = ConvertTo-iSOCDefenderDetectionColumn -Identifier $identifier

        switch ($type) {
            'impactedUserAsset' {
                $collection = 'accounts'
                $property = switch -Regex ($identifier) {
                    'ObjectId$' { 'aadUserIdColumn'; break }
                    'Sid$' { 'sidColumn'; break }
                    'Upn$' { 'upnColumn'; break }
                    'Name$' { 'nameColumn'; break }
                    'Domain$' { 'ntDomainColumn'; break }
                    default { throw "impactedUserAsset identifier '$identifier' has no account entity column property." }
                }
            }
            'impactedDeviceAsset' {
                $collection = 'hosts'
                $property = switch -Regex ($identifier) {
                    'Id$' { 'deviceIdColumn'; break }
                    'Name$' { 'nameColumn'; break }
                    default { throw "impactedDeviceAsset identifier '$identifier' has no host entity column property." }
                }
            }
            'impactedMailboxAsset' {
                $collection = 'mailboxes'
                if ($identifier -notmatch 'Address$') {
                    throw "impactedMailboxAsset identifier '$identifier' has no mailbox entity column property."
                }
                $property = 'primaryAddressColumn'
            }
            default { throw "Unknown impactedAssets type '$type'." }
        }

        if (-not $mappings.Contains($collection)) {
            $mappings[$collection] = [System.Collections.Generic.List[object]]::new()
        }
        $mappings[$collection].Add([ordered]@{ $property = $column })
    }

    $result = [ordered]@{}
    foreach ($key in $mappings.Keys) { $result[$key] = @($mappings[$key]) }
    $result
}

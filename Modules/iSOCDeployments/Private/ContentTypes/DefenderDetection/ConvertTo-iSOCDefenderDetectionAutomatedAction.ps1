#Requires -Version 7.2

<#
.SYNOPSIS
    Build detectionAction.automatedActions from retired responseActions.

.DESCRIPTION
    Copied from ConvertTo-DetectionAutomatedAction
    (Deploy/content/Deploy-DefenderDetections.ps1).

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/DefenderDetection/ConvertTo-iSOCDefenderDetectionAutomatedAction.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.0
    Last Updated: 2026-11-03
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function ConvertTo-iSOCDefenderDetectionAutomatedAction {
    <#
    .SYNOPSIS
        Return the automated actions, grouped by member.

    .DESCRIPTION
        Each response action becomes one entry under its new member. An
        action with one identifier fills the member's column property; one
        with several comma-separated identifiers fills the property each
        token names. An action type or token with no mapping throws, so
        nothing is guessed. The isolation type and device group names are
        carried over.

    .PARAMETER ResponseActions
        The retired detectionAction.responseActions.

    .OUTPUTS
        [System.Collections.Specialized.OrderedDictionary] Member name to its
        list of entries.

    .EXAMPLE
        ConvertTo-iSOCDefenderDetectionAutomatedAction -ResponseActions $action['responseActions']
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [AllowNull()]
        [object[]] $ResponseActions
    )

    $contract = Get-iSOCDefenderDetectionContract
    $actions = [ordered]@{}
    foreach ($action in @($ResponseActions)) {
        if ($null -eq $action) { continue }
        $type = ([string]$action['@odata.type']) -replace '^#?microsoft\.graph\.security\.', ''
        if (-not $contract.LegacyResponseActionMap.ContainsKey($type)) {
            throw "Unknown responseActions type '$type'."
        }
        $target = $contract.LegacyResponseActionMap[$type]
        $entry = [ordered]@{}

        $tokens = @(([string]$action['identifier']) -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        if ($target.Column -and $tokens.Count -eq 1) {
            $entry[$target.Column] = ConvertTo-iSOCDefenderDetectionColumn -Identifier $tokens[0]
        }
        else {
            foreach ($token in $tokens) {
                if (-not $contract.LegacyMultiIdentifierColumns.ContainsKey($token)) {
                    throw "responseActions '$type' identifier '$token' has no automated action column property."
                }
                $entry[$contract.LegacyMultiIdentifierColumns[$token]] = ConvertTo-iSOCDefenderDetectionColumn -Identifier $token
            }
        }
        if ($action.Contains('isolationType')) { $entry['isolationType'] = [string]$action['isolationType'] }
        if ($action.Contains('deviceGroupNames')) { $entry['deviceGroupNames'] = @($action['deviceGroupNames']) }

        if (-not $actions.Contains($target.Member)) {
            $actions[$target.Member] = [System.Collections.Generic.List[object]]::new()
        }
        $actions[$target.Member].Add($entry)
    }

    $result = [ordered]@{}
    foreach ($key in $actions.Keys) { $result[$key] = @($actions[$key]) }
    $result
}

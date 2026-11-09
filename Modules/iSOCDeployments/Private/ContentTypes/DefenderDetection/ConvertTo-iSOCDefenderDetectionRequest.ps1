#Requires -Version 7.6

<#
.SYNOPSIS
    ToRequest handler for Defender XDR custom detections: the body deploy
    sends.

.DESCRIPTION
    Copied from ConvertTo-GraphDetectionBody
    (Deploy/content/Deploy-DefenderDetections.ps1), unchanged in what it
    sends. Tests/iSOCDeployments/DefenderDetection.Tests.ps1 holds every
    detection in Content/DefenderCustomDetections/ to the request the
    script builds.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/DefenderDetection/ConvertTo-iSOCDefenderDetectionRequest.ps1
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

function ConvertTo-iSOCDefenderDetectionRequest {
    <#
    .SYNOPSIS
        Build the Graph detectionRule request body for one file.

    .DESCRIPTION
        The body for an update: displayName, status (enabled unless the
        rule says otherwise), description when set, the query, the
        canonical frequency and the detection action. The severity is sent
        in lower case. organizationalScope is sent as null unless the rule
        sets device groups, and automatedActions as an empty set unless the
        rule sets some, so the repository file stays the source of truth on
        update. -ForCreate adds the file's id, which Graph requires when a
        rule is created and does not accept on update. The function reads
        nothing outside the item and sends nothing.

    .PARAMETER Item
        A repository item from Read-iSOCDefenderDetectionRepo that passed
        Test-iSOCDefenderDetection.

    .PARAMETER ForCreate
        Add the client-provided id, for a rule the tenant does not have.

    .OUTPUTS
        [pscustomobject] iSOCDeployments.Request: ContentType, Identity,
        ResourceName (the file's id; nothing when it has none) and Body.

    .EXAMPLE
        $request = ConvertTo-iSOCDefenderDetectionRequest -Item $item -ForCreate
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Item,

        [switch] $ForCreate
    )

    $Rule = $Item.Rule
    $source = $Rule['detectionAction']['alertTemplate']
    $alertTemplate = [ordered]@{
        title    = [string]$source['title']
        severity = ([string]$source['severity']).ToLowerInvariant()
        tactics  = @($source['tactics'])
    }
    foreach ($optional in 'description', 'recommendedActions', 'entityMappings', 'customDetails') {
        if ($source.Contains($optional) -and $null -ne $source[$optional]) { $alertTemplate[$optional] = $source[$optional] }
    }

    $sourceAction = $Rule['detectionAction']
    $detectionAction = [ordered]@{
        alertTemplate       = $alertTemplate
        automatedActions    = if ($sourceAction['automatedActions'] -is [System.Collections.IDictionary]) { $sourceAction['automatedActions'] } else { @{} }
        organizationalScope = $null
    }
    if ($sourceAction['organizationalScope'] -is [System.Collections.IDictionary] -and @($sourceAction['organizationalScope']['deviceGroups']).Count -gt 0) {
        $detectionAction.organizationalScope = [ordered]@{ deviceGroups = @($sourceAction['organizationalScope']['deviceGroups']) }
    }
    if ($sourceAction['incidentConfiguration'] -is [System.Collections.IDictionary]) {
        $detectionAction.incidentConfiguration = $sourceAction['incidentConfiguration']
    }

    $body = [ordered]@{}
    if ($ForCreate) { $body.id = [string]$Rule['id'] }
    $body.displayName = [string]$Rule['displayName']
    $body.status = if ($Rule.Contains('status') -and $Rule['status']) { [string]$Rule['status'] } else { 'enabled' }
    if ($Rule.Contains('description') -and $Rule['description']) { $body.description = [string]$Rule['description'] }
    $body.queryCondition = [ordered]@{ queryText = [string]$Rule['queryCondition']['queryText'] }
    $body.schedule = [ordered]@{ frequency = ConvertTo-iSOCDefenderDetectionFrequency -Value ([string]$Rule['schedule']['frequency']) }
    $body.detectionAction = $detectionAction

    [pscustomobject]@{
        PSTypeName   = 'iSOCDeployments.Request'
        ContentType  = $Item.ContentType
        Identity     = $Item.Identity
        ResourceName = [string]$Rule['id']
        Body         = $body
    }
}

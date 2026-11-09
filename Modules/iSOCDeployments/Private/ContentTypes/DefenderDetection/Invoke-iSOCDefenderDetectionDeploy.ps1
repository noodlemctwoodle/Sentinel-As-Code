#Requires -Version 7.6

<#
.SYNOPSIS
    Deploy handler for Defender XDR custom detections: update a rule the
    tenant has, or create it with the file's id.

.DESCRIPTION
    Copied from the send in Deploy-DefenderDetections
    (Deploy/content/Deploy-DefenderDetections.ps1). Graph has no PUT for
    detection rules, so the engine's shared send does not fit: an existing
    rule is updated with PATCH at its id, and a new one is created with
    POST to the collection, carrying the id the file gives it.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/DefenderDetection/Invoke-iSOCDefenderDetectionDeploy.ps1
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

function Invoke-iSOCDefenderDetectionDeploy {
    <#
    .SYNOPSIS
        Send one detection and say how it went.

    .DESCRIPTION
        - A file that uses the retired Graph fields is warned about, naming
          them; the translated rule is what is sent.
        - A rule whose display name the tenant already has is updated in
          place: its id was set when it was created and cannot change.
        - A new rule is created with the file's id. A new rule whose file
          has no id cannot be created, since Graph needs a client-provided
          id: it fails, and under -WhatIf it is reported as one that would.
        - When Graph refuses a request, the body that was sent is logged
          and the error is thrown, so deploy reports the rule failed.

    .PARAMETER Run
        The deployment run.

    .PARAMETER ContentType
        The Defender detection content type.

    .PARAMETER Item
        A repository item that passed Test-iSOCDefenderDetection.

    .OUTPUTS
        [hashtable] Outcome (Deployed or WhatIf) and Reason.

    .EXAMPLE
        Invoke-iSOCDefenderDetectionDeploy -Run $run -ContentType $detections -Item $item
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Run,

        [Parameter(Mandatory)]
        [psobject] $ContentType,

        [Parameter(Mandatory)]
        [psobject] $Item
    )

    if (@($Item.LegacyFields).Count -gt 0) {
        Write-iSOCLog "'$($Item.RelativePath)' uses retired Graph fields ($($Item.LegacyFields -join ', ')); deploying a translated copy. Convert the file to the current shape (see Docs/Content/Defender-Custom-Detections.md)." -Level Warning
    }

    $rule = $Item.Rule
    $name = [string]$rule['displayName']
    $frequency = ConvertTo-iSOCDefenderDetectionFrequency -Value ([string]$rule['schedule']['frequency'])
    Write-iSOCLog "  Schedule: $frequency, severity: $($rule['detectionAction']['alertTemplate']['severity'])"

    $existing = Get-iSOCDefenderDetectionRuleId -Run $Run -ContentType $ContentType
    $apiVersion = Get-iSOCApiVersion $ContentType.ApiVersion
    $send = {
        param([string] $Method, [string] $Path, [psobject] $Request)
        try {
            Invoke-iSOCRestRequest -Method $Method -Api Graph -Context $Run.Context -Path $Path -ApiVersion $apiVersion -Body $Request.Body
        }
        catch {
            Write-iSOCLog "Request body: $(ConvertTo-Json -InputObject $Request.Body -Depth 20)" -Level Warning
            throw
        }
    }

    if ($existing.ContainsKey($name)) {
        $id = $existing[$name]
        $request = ConvertTo-iSOCDefenderDetectionRequest -Item $Item
        if (-not $PSCmdlet.ShouldProcess($Item.RelativePath, "Update Defender XDR custom detection '$name'")) {
            Write-iSOCLog "[WhatIf] Would update: $name (ID: $id)"
            return @{ Outcome = 'WhatIf'; Reason = '' }
        }
        & $send PATCH (Get-iSOCResourcePath -Context $Run.Context -ContentType $ContentType -Name $id) $request | Out-Null
        Write-iSOCLog "Updated: $name (ID: $id)" -Level Success
        return @{ Outcome = 'Deployed'; Reason = '' }
    }

    if ([string]::IsNullOrWhiteSpace([string]$rule['id'])) {
        $problem = "'$name' does not exist yet and the file has no 'id'; Graph needs a client-provided id to create a rule."
        if (-not $PSCmdlet.ShouldProcess($Item.RelativePath, "Create Defender XDR custom detection '$name'")) {
            Write-iSOCLog "[WhatIf] Would fail: $problem" -Level Warning
            return @{ Outcome = 'WhatIf'; Reason = "would fail: $problem" }
        }
        throw $problem
    }

    $request = ConvertTo-iSOCDefenderDetectionRequest -Item $Item -ForCreate
    if (-not $PSCmdlet.ShouldProcess($Item.RelativePath, "Create Defender XDR custom detection '$name'")) {
        Write-iSOCLog "[WhatIf] Would create: $name (ID: $($request.ResourceName))"
        return @{ Outcome = 'WhatIf'; Reason = '' }
    }
    $result = & $send POST (Get-iSOCResourcePath -Context $Run.Context -ContentType $ContentType) $request
    Write-iSOCLog "Created: $name (ID: $(Get-iSOCPropertyValue -InputObject $result -Path 'id'))" -Level Success
    @{ Outcome = 'Deployed'; Reason = '' }
}

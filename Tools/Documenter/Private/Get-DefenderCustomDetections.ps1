#Requires -Version 7.2

<#
.SYNOPSIS
    Read Defender XDR custom detection rules from Microsoft Graph and resolve
    the tables each one queries.

.DESCRIPTION
    Microsoft Graph (beta) security/rules/detectionRules lists the custom
    detection rules defined in the Defender portal. Two credentials can carry
    the call: the Azure PowerShell context (Invoke-AzRestMethod, which needs an
    identity holding the CustomDetection.Read.All application permission, the
    pipeline case) or a Microsoft Graph PowerShell SDK session
    (Invoke-MgGraphRequest after Connect-MgGraph -Scopes CustomDetection.Read.All,
    the interactive case: Azure PowerShell's own app cannot request that
    delegated scope). The Graph SDK session is tried first when one is
    present, then the Azure PowerShell context. A 401 or 403 throws with the
    permission named so the collector records a failed capture, never an
    empty list.

.NOTES
    File:         Tools/Documenter/Private/Get-DefenderCustomDetections.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-12
    Version:      0.1.0
    Last Updated: 2026-10-12
    Requires:     PowerShell 7.2+, Az.Accounts or Microsoft.Graph.Authentication

    This file defines functions rather than running.
#>

function Get-DefenderCustomDetections {
    <#
    .SYNOPSIS
        Return every custom detection rule, following @odata.nextLink.

    .PARAMETER PageSize
        Rules per page (Graph allows up to 100).

    .OUTPUTS
        [object[]] The detectionRule objects as Graph returns them.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param([Parameter(Mandatory = $false)] [ValidateRange(1, 100)] [int] $PageSize = 100)

    $uri = "https://graph.microsoft.com/beta/security/rules/detectionRules?`$top=$PageSize"
    $rules = [System.Collections.Generic.List[object]]::new()
    $useMg = $false
    if (Get-Command Invoke-MgGraphRequest -ErrorAction SilentlyContinue) {
        $mgCtx = $null
        try { $mgCtx = Get-MgContext -ErrorAction SilentlyContinue } catch { $mgCtx = $null }
        if ($mgCtx) { $useMg = $true }
    }
    $pages = 0
    while ($uri -and $pages -lt 50) {
        $pages++
        if ($useMg) {
            try {
                $body = Invoke-MgGraphRequest -Method GET -Uri $uri -OutputType PSObject -ErrorAction Stop
            } catch {
                $msg = $_.Exception.Message
                if ($msg -match '401|403|Forbidden|Unauthorized|Authorization_RequestDenied') {
                    throw "Microsoft Graph refused security/rules/detectionRules for the Graph SDK session: $msg. Connect-MgGraph -Scopes 'CustomDetection.Read.All' with an account allowed to read custom detections, or grant CustomDetection.Read.All (application) to the pipeline identity."
                }
                throw
            }
        } else {
            try {
                $resp = Invoke-AzRestMethod -Uri $uri -Method GET -ErrorAction Stop
            } catch {
                throw "Azure PowerShell could not call Microsoft Graph: $($_.Exception.Message.Trim()) For an interactive run, Connect-MgGraph -Scopes 'CustomDetection.Read.All' in the same session and the capture will use that session; a pipeline identity needs the CustomDetection.Read.All application permission."
            }
            if ($resp.StatusCode -eq 401 -or $resp.StatusCode -eq 403) {
                throw "Microsoft Graph returned $($resp.StatusCode) for security/rules/detectionRules. The Azure PowerShell identity needs the CustomDetection.Read.All application permission; for an interactive run, Connect-MgGraph -Scopes 'CustomDetection.Read.All' first and the capture will use that session."
            }
            if ($resp.StatusCode -ge 400) { throw "Microsoft Graph returned $($resp.StatusCode): $($resp.Content)" }
            $body = $resp.Content | ConvertFrom-Json -Depth 32
        }
        foreach ($d in @($body.value)) { if ($d) { $rules.Add($d) } }
        $uri = if ($body.PSObject.Properties['@odata.nextLink']) { [string]$body.'@odata.nextLink' } else { $null }
    }
    return $rules.ToArray()
}

function Get-CustomDetectionTableReferences {
    <#
    .SYNOPSIS
        Project detection rules to id, name, state, severity, period, last
        modified and the tables their query reads.

    .PARAMETER Detections
        detectionRule objects from Get-DefenderCustomDetections (or a fixture).

    .OUTPUTS
        [pscustomobject[]] RuleId, RuleName, Enabled, Severity, Period,
        LastModified, Tables.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param([Parameter(Mandatory = $false)] [AllowNull()] [object[]] $Detections)

    $out = foreach ($d in @($Detections)) {
        if ($null -eq $d) { continue }
        $qc = if ($d.PSObject.Properties['queryCondition']) { $d.queryCondition } else { $null }
        $q = if ($qc -and $qc.PSObject.Properties['queryText']) { [string]$qc.queryText } else { '' }
        $da = if ($d.PSObject.Properties['detectionAction']) { $d.detectionAction } else { $null }
        $at = if ($da -and $da.PSObject.Properties['alertTemplate']) { $da.alertTemplate } else { $null }
        $sc = if ($d.PSObject.Properties['schedule']) { $d.schedule } else { $null }
        [pscustomobject]@{
            RuleId       = [string]$(if ($d.PSObject.Properties['id']) { $d.id } else { '' })
            RuleName     = [string]$(if ($d.PSObject.Properties['displayName']) { $d.displayName } else { '' })
            Enabled      = [bool]$(if ($d.PSObject.Properties['isEnabled']) { $d.isEnabled } else { $false })
            Severity     = [string]$(if ($at -and $at.PSObject.Properties['severity']) { $at.severity } else { '' })
            Period       = [string]$(if ($sc -and $sc.PSObject.Properties['period']) { $sc.period } else { '' })
            LastModified = [string]$(if ($d.PSObject.Properties['lastModifiedDateTime']) { $d.lastModifiedDateTime } else { '' })
            Tables       = @(Resolve-KqlTableNames -Query $q)
        }
    }
    return @($out)
}

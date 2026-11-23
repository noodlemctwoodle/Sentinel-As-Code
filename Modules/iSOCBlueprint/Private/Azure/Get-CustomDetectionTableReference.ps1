#Requires -Version 7.6

<#
.SYNOPSIS
    Project detection rules to id, name, state, severity, period, last modified and the tables...

.DESCRIPTION
    One of the helpers beside Get-DefenderCustomDetection.ps1, which describes the whole.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Azure/Get-CustomDetectionTableReference.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-12
    Version:      0.1.0
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+, Az.Accounts or Microsoft.Graph.Authentication

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-CustomDetectionTableReference {
    <#
    .SYNOPSIS
        Project detection rules to id, name, state, severity, period, last
        modified and the tables their query reads.

    .PARAMETER Detections
        detectionRule objects from Get-DefenderCustomDetection (or a fixture).

    .OUTPUTS
        [pscustomobject[]] RuleId, RuleName, Enabled, Severity, Period,
        LastModified, Tables.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]], [object[]])]
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
            Tables       = @(Resolve-KqlTableName -Query $q)
        }
    }
    return @($out)
}

#Requires -Version 7.6

<#
.SYNOPSIS
    The MITRE tactics in order, and the rule count that counts as covered.

.DESCRIPTION
    Defines $script:MitreTactics and $script:MitreCoveredThreshold for the SharePoint site build.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Site/Data/MitreTactics.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Component:    iSOC Blueprint, SharePoint site build
    Requires:     PowerShell 7.6+

    This file defines values rather than running.
#>

# MITRE internal-name -> (TA id, display) mapping.
$script:MitreTactics = [ordered]@{
    'Reconnaissance'      = @('TA0043', 'Reconnaissance')
    'ResourceDevelopment' = @('TA0042', 'Resource Development')
    'InitialAccess'       = @('TA0001', 'Initial Access')
    'Execution'           = @('TA0002', 'Execution')
    'Persistence'         = @('TA0003', 'Persistence')
    'PrivilegeEscalation' = @('TA0004', 'Privilege Escalation')
    'DefenseEvasion'      = @('TA0005', 'Defense Evasion')
    'CredentialAccess'    = @('TA0006', 'Credential Access')
    'Discovery'           = @('TA0007', 'Discovery')
    'LateralMovement'     = @('TA0008', 'Lateral Movement')
    'Collection'          = @('TA0009', 'Collection')
    'CommandAndControl'   = @('TA0011', 'Command and Control')
    'Exfiltration'        = @('TA0010', 'Exfiltration')
    'Impact'              = @('TA0040', 'Impact')
}

# A tactic counts as Covered at this many enabled rules, Thin below it.
$script:MitreCoveredThreshold = 3

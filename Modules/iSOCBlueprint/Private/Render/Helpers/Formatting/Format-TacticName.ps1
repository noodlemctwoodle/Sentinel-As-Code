#Requires -Version 7.6

<#
.SYNOPSIS
    Show a tactic by MITRE's own name.

.DESCRIPTION
    Helper for the Blueprint renderer (Invoke-iSOCBlueprintRender).

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Helpers/Formatting/Format-TacticName.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.1
    Last Updated: 2026-11-23
    Requires:     PowerShell 7.6+

    This file defines functions rather than running. Per-parameter detail
    lives on each function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Format-TacticName {
    <#
    .SYNOPSIS
        Show a tactic by MITRE's own name.

    .DESCRIPTION
        A tactic as the Sentinel API returns it (CredentialAccess) by MITRE's own
        name (Credential Access, Command and Control), as the ATT&CK page and the
        dashboard write it: each word capitalised but 'and'. The name goes through
        ConvertTo-BlueprintWord; a single word that comes back unchanged is
        returned as it is.

    .PARAMETER Tactic
        The tactic name.

    .OUTPUTS
        [string].
    #>
    [CmdletBinding()]
    param([string]$Tactic)
    $words = ConvertTo-BlueprintWord $Tactic.Trim()
    if ($words -eq $Tactic.Trim() -and $words -notmatch '\s') { return $words }
    (@($words -split ' ' | ForEach-Object { if ($_ -ceq 'and') { $_ } else { $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1) } }) -join ' ')
}

#Requires -Version 7.2

<#
.SYNOPSIS
    Where a definition holds what looks like a secret in plain text.

.DESCRIPTION
    Copied from Find-PlaintextSecret and Find-PlaintextSecretInNode
    (847ef86:Tools/Export-Playbooks.ps1), one function walking itself.

.NOTES
    File:         Modules/iSOCDeployments/Private/Export/Find-iSOCPlaintextSecret.ps1
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

function Find-iSOCPlaintextSecret {
    <#
    .SYNOPSIS
        Return the path of each literal value that looks like a secret.

    .DESCRIPTION
        Flags literal values in three places: credential headers
        (Authorization, x-api-key and the like), the secret fields of an
        HTTP authentication block (password, secret, pfx, value), and a
        uri with a key-bearing query parameter (code, sig, key, apikey). A
        value that starts with @ or holds @{ is a workflow expression, a
        Key Vault or parameter lookup typically, and is not flagged.

    .PARAMETER Node
        The definition, or the part of it being walked.

    .PARAMETER Path
        Where the node is, for the paths returned.

    .OUTPUTS
        [string] One path per finding, such as
        actions.Lookup.inputs.headers.x-apikey.

    .EXAMPLE
        Find-iSOCPlaintextSecret -Node $app.properties.definition
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]
        [object] $Node,

        [string] $Path = ''
    )

    if ($null -eq $Node -or $Node -is [string]) { return }

    $isObject = $Node -is [System.Management.Automation.PSCustomObject] -or $Node -is [System.Collections.IDictionary]
    if (-not $isObject) {
        if ($Node -is [System.Collections.IEnumerable]) {
            $i = 0
            foreach ($item in $Node) {
                Find-iSOCPlaintextSecret -Node $item -Path "$Path[$i]"
                $i++
            }
        }
        return
    }

    $parent = ($Path -split '\.')[-1]
    foreach ($entry in @(Get-iSOCPropertyEntry -InputObject $Node)) {
        $name = $entry.Name
        $value = $entry.Value
        $childPath = if ($Path) { "$Path.$name" } else { $name }

        if ($value -is [string]) {
            $isLiteral = $value -and -not $value.StartsWith('@') -and $value -notmatch '@\{'
            $flag = $false
            if ($parent -eq 'headers' -and $name -match '^(authorization|x-api-key|api-key|apikey|x-apikey|ocp-apim-subscription-key|x-functions-key)$') { $flag = $isLiteral }
            elseif ($parent -eq 'authentication' -and $name -match '^(password|secret|pfx|value)$') { $flag = $isLiteral }
            elseif ($name -eq 'uri' -and $value -match '[?&](code|sig|key|apikey|api_key|api-key)=(?!@)[^&]+') { $flag = $true }
            if ($flag) { $childPath }
            continue
        }
        Find-iSOCPlaintextSecret -Node $value -Path $childPath
    }
}

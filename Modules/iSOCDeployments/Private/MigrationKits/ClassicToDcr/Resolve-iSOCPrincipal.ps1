#Requires -Version 7.2

<#
.SYNOPSIS
    Turn an application id or an object id into a principal's object id and type.

.DESCRIPTION
    An application id is looked up among the service principals; anything
    else is taken as an object id, typed from the directory when it can be.

.NOTES
    File:         Modules/iSOCDeployments/Private/MigrationKits/ClassicToDcr/Resolve-iSOCPrincipal.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.0
    Last Updated: 2026-11-04
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Resolve-iSOCPrincipal {
    <#
    .SYNOPSIS
        Turn an application id or an object id into a principal's object id
        and type.

    .DESCRIPTION
        The identity is looked up first as a service principal's application
        (client) id, through Microsoft Graph with the Az sign-in. When it is
        not one it is taken as an object id (a user, group, managed identity
        or service principal), and its type is read from the directory, so
        the role assignment can say what it is assigned to. A type that
        cannot be read is left empty, and Azure looks the principal up.

    .PARAMETER Context
        The workspace context.

    .PARAMETER Identity
        An application id or an object id.

    .OUTPUTS
        [pscustomobject] ObjectId and PrincipalType (ServicePrincipal, User,
        Group or empty).

    .EXAMPLE
        Resolve-iSOCPrincipal -Context $ctx -Identity $appId
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Context,

        [Parameter(Mandatory)]
        [string] $Identity
    )

    try {
        $filter = [Uri]::EscapeDataString("appId eq '$Identity'")
        $sp = @(Invoke-iSOCRestRequest -Method GET -Api Graph -ApiVersion 'v1.0' -Path "/servicePrincipals?`$filter=$filter" -Context $Context) | Select-Object -First 1
        $id = [string](Get-iSOCPropertyValue -InputObject $sp -Path 'id')
        if ($id) { return [pscustomobject]@{ ObjectId = $id; PrincipalType = 'ServicePrincipal' } }
    }
    catch {
        Write-iSOCLog "Not an application ID, treating '$Identity' as an object ID: $($_.Exception.Message.Split([char]10)[0])" -Level Debug
    }

    $type = ''
    try {
        $object = Invoke-iSOCRestRequest -Method GET -Api Graph -ApiVersion 'v1.0' -Path "/directoryObjects/$Identity" -Context $Context -AllowNotFound
        $odata = if ($object -and $object.PSObject.Properties['@odata.type']) { [string]$object.'@odata.type' } else { '' }
        $type = switch ($odata) {
            '#microsoft.graph.user' { 'User' }
            '#microsoft.graph.group' { 'Group' }
            '#microsoft.graph.servicePrincipal' { 'ServicePrincipal' }
            default { '' }
        }
    }
    catch {
        Write-iSOCLog "Could not read the type of '$Identity': $($_.Exception.Message.Split([char]10)[0])" -Level Debug
    }
    [pscustomobject]@{ ObjectId = $Identity; PrincipalType = $type }
}

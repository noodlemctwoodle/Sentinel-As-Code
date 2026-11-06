#Requires -Version 7.2

<#
.SYNOPSIS
    Write a parsed ARM expression as a Bicep expression.

.NOTES
    File:         Modules/iSOCDeployments/Private/Bicep/ConvertTo-iSOCBicepExpression.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-06
    Version:      0.1.0
    Last Updated: 2026-11-06
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function ConvertTo-iSOCBicepExpression {
    <#
    .SYNOPSIS
        Return the Bicep text of a node from ConvertFrom-iSOCArmExpression.

    .DESCRIPTION
        - parameters('X') and variables('X') become the identifiers the
          symbol table gives them; one the template does not declare throws.
        - concat() of strings becomes an interpolated string ('a${b}c'):
          when an argument is a string literal, or every argument is known
          to be a string (a string parameter or variable, a resource group
          or subscription property, resourceId, guid and the like). Any
          other concat() stays concat().
        - resourceId(type, name) naming a resource in the same template
          (names compared without case, as ARM does) becomes that
          resource's symbolic reference (symbol.id), except inside that
          resource itself.
        - true(), false() and null() become literals; if, equals, not, and,
          or, createArray and createObject become Bicep operators and
          literals.
        - Any other function is written as a Bicep function call, with the
          Bicep spelling of the name where it differs only in case.

    .PARAMETER Node
        The node.

    .PARAMETER Symbols
        The symbol table from ConvertTo-iSOCBicepTemplate: Parameters,
        ParameterTypes, Variables and VariableValues (hashtables keyed by
        the ARM name, which compare without case as ARM does), Resources
        (Type, NameText, Symbol) and Current (the symbol of the resource
        being written, or null).

    .OUTPUTS
        [string] The Bicep expression.

    .EXAMPLE
        ConvertTo-iSOCBicepExpression -Node $node -Symbols $symbols
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Node,

        [Parameter(Mandatory)]
        [psobject] $Symbols
    )

    $spelling = @{
        resourcegroup = 'resourceGroup'; resourceid = 'resourceId'; subscriptionresourceid = 'subscriptionResourceId'
        tenantresourceid = 'tenantResourceId'; extensionresourceid = 'extensionResourceId'; uniquestring = 'uniqueString'
        tolower = 'toLower'; toupper = 'toUpper'; base64tostring = 'base64ToString'; uricomponent = 'uriComponent'
        uricomponenttostring = 'uriComponentToString'; utcnow = 'utcNow'; startswith = 'startsWith'; endswith = 'endsWith'
        indexof = 'indexOf'; lastindexof = 'lastIndexOf'; padleft = 'padLeft'; listkeys = 'listKeys'; datauri = 'dataUri'
        datauritostring = 'dataUriToString'; newguid = 'newGuid'; managementgroup = 'managementGroup'; pickzones = 'pickZones'
        managementgroupresourceid = 'managementGroupResourceId'; datetimeadd = 'dateTimeAdd'
    }
    $stringFunctions = @(
        'format', 'tolower', 'toupper', 'string', 'uniquestring', 'guid', 'replace', 'substring', 'trim', 'resourceid',
        'subscriptionresourceid', 'tenantresourceid', 'extensionresourceid', 'managementgroupresourceid', 'base64',
        'base64tostring', 'uri', 'uricomponent', 'uricomponenttostring', 'utcnow', 'newguid', 'padleft', 'datauri'
    )
    $contextProperties = @('location', 'name', 'id', 'subscriptionid', 'tenantid', 'displayname', 'type')

    $write = { param($Item) ConvertTo-iSOCBicepExpression -Node $Item -Symbols $Symbols }
    $nameArgument = {
        param($Call)
        $first = @($Call.Arguments)[0]
        if (@($Call.Arguments).Count -ne 1 -or $first.Kind -ne 'String') { throw "$($Call.Name)() needs one string argument." }
        $first.Value
    }

    $isString = $null
    $isString = {
        param($Item)
        switch ($Item.Kind) {
            'String' { return $true }
            'Member' {
                return ($Item.Target.Kind -eq 'Call' -and $Item.Target.Name.ToLowerInvariant() -in 'resourcegroup', 'subscription', 'tenant', 'deployment' -and
                    $Item.Name.ToLowerInvariant() -in $contextProperties)
            }
            'Call' {
                $name = $Item.Name.ToLowerInvariant()
                if ($name -in $stringFunctions) { return $true }
                if ($name -eq 'concat') { return (@($Item.Arguments | Where-Object { -not (& $isString $_) }).Count -eq 0) }
                if ($name -eq 'parameters') { return ($Symbols.ParameterTypes[(& $nameArgument $Item)] -in 'string', 'securestring') }
                if ($name -eq 'variables') {
                    $value = $Symbols.VariableValues[(& $nameArgument $Item)]
                    if ($value -isnot [string]) { return $false }
                    if ($value.StartsWith('[') -and $value.EndsWith(']') -and -not $value.StartsWith('[[')) {
                        return (& $isString (ConvertFrom-iSOCArmExpression -Expression $value.Substring(1, $value.Length - 2)))
                    }
                    return $true
                }
                return $false
            }
            default { return $false }
        }
    }

    switch ($Node.Kind) {
        'String' { return (ConvertTo-iSOCBicepString -Value $Node.Value) }
        'Number' { return [string]$Node.Value }
        'Member' { return (& $write $Node.Target) + '.' + $Node.Name }
        'Index' { return (& $write $Node.Target) + '[' + (& $write $Node.Index) + ']' }
    }

    $arguments = @($Node.Arguments)
    $lower = $Node.Name.ToLowerInvariant()
    switch ($lower) {
        'parameters' {
            $armName = & $nameArgument $Node
            if (-not $Symbols.Parameters.ContainsKey($armName)) { throw "parameters('$armName') names a parameter the template does not declare." }
            return $Symbols.Parameters[$armName]
        }
        'variables' {
            $armName = & $nameArgument $Node
            if (-not $Symbols.Variables.ContainsKey($armName)) { throw "variables('$armName') names a variable the template does not declare." }
            return $Symbols.Variables[$armName]
        }
        'true' { return 'true' }
        'false' { return 'false' }
        'null' { return 'null' }
        'if' { return '(' + (& $write $arguments[0]) + ' ? ' + (& $write $arguments[1]) + ' : ' + (& $write $arguments[2]) + ')' }
        'equals' { return '(' + (& $write $arguments[0]) + ' == ' + (& $write $arguments[1]) + ')' }
        'not' { return '!(' + (& $write $arguments[0]) + ')' }
        'and' { return '(' + ((@($arguments | ForEach-Object { & $write $_ })) -join ' && ') + ')' }
        'or' { return '(' + ((@($arguments | ForEach-Object { & $write $_ })) -join ' || ') + ')' }
        'createarray' { return '[' + ((@($arguments | ForEach-Object { & $write $_ })) -join ', ') + ']' }
        'createobject' {
            $pairs = for ($i = 0; $i -lt $arguments.Count; $i += 2) {
                if ($arguments[$i].Kind -ne 'String') { throw 'createObject() needs string keys.' }
                $key = $arguments[$i].Value
                $label = if ($key -match '^[A-Za-z_][A-Za-z0-9_]*$') { $key } else { ConvertTo-iSOCBicepString -Value $key }
                "${label}: $(& $write $arguments[$i + 1])"
            }
            return '{ ' + ($pairs -join ', ') + ' }'
        }
        'concat' {
            $literalArgument = @($arguments | Where-Object { $_.Kind -eq 'String' }).Count -gt 0
            if ($literalArgument -or (& $isString $Node)) {
                $parts = [System.Text.StringBuilder]::new()
                $flatten = $null
                $flatten = {
                    param($Items)
                    foreach ($item in $Items) {
                        if ($item.Kind -eq 'String') { [void]$parts.Append((ConvertTo-iSOCBicepString -Value $item.Value -Fragment)) }
                        elseif ($item.Kind -eq 'Call' -and $item.Name -ieq 'concat' -and (& $isString $item)) { & $flatten @($item.Arguments) }
                        else { [void]$parts.Append('${' + (& $write $item) + '}') }
                    }
                }
                & $flatten $arguments
                return "'" + $parts.ToString() + "'"
            }
        }
        'resourceid' {
            if ($arguments.Count -eq 2 -and $arguments[0].Kind -eq 'String') {
                $nameText = ConvertTo-iSOCArmExpressionText -Node $arguments[1]
                $target = @($Symbols.Resources | Where-Object { $_.Type -ieq $arguments[0].Value -and $_.NameText -ieq $nameText })
                if ($target.Count -eq 1 -and $target[0].Symbol -ne $Symbols.Current) { return "$($target[0].Symbol).id" }
            }
        }
    }

    $functionName = if ($spelling.ContainsKey($lower)) { $spelling[$lower] } else { $Node.Name }
    $functionName + '(' + ((@($arguments | ForEach-Object { & $write $_ })) -join ', ') + ')'
}

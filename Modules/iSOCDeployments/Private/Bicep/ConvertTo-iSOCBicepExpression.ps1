#Requires -Version 7.6

<#
.SYNOPSIS
    Write a parsed ARM expression as a Bicep expression.

.NOTES
    File:         Modules/iSOCDeployments/Private/Bicep/ConvertTo-iSOCBicepExpression.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-06
    Version:      0.2.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+

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
          A string that is exactly a subscription-level resource id
          ('/subscriptions/', subscription().subscriptionId,
          '/providers/<namespace>/<type>/' and a name, with any further
          type and name pairs) becomes subscriptionResourceId(); a resource
          group id stays a string, as the playbook order reads those.
        - resourceGroup().location becomes the template's location
          parameter when the symbol table names one (Location).
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
        (Type, NameText, Symbol), Current (the symbol of the resource
        being written, or null) and, optionally, Location (the identifier
        resourceGroup().location is written as, or null).

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

    # A string that is exactly a subscription-level resource id, as
    # '/subscriptions/', subscription().subscriptionId, '/providers/<ns>/<type>/'
    # and a name, with more type and name pairs after it: the items of a
    # concat, flattened. Returns subscriptionResourceId(...), or nothing
    # when the string is anything else. A resource group id is left alone.
    $subscriptionResourceIdOf = {
        param($Items)
        $segments = [System.Collections.Generic.List[object]]::new()
        $current = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $Items) {
            if ($item.Kind -ne 'String') { $current.Add($item); continue }
            $pieces = $item.Value.Split('/')
            for ($i = 0; $i -lt $pieces.Count; $i++) {
                if ($i -gt 0) {
                    $segments.Add($current)
                    $current = [System.Collections.Generic.List[object]]::new()
                }
                if ($pieces[$i]) { $current.Add([pscustomobject]@{ Kind = 'String'; Value = $pieces[$i] }) }
            }
        }
        $segments.Add($current)
        $text = { param($Segment) if ($Segment.Count -eq 1 -and $Segment[0].Kind -eq 'String') { $Segment[0].Value } else { $null } }
        if ($segments.Count -lt 7 -or ($segments.Count - 5) % 2 -ne 0 -or $segments[0].Count -ne 0) { return $null }
        if ((& $text $segments[1]) -ine 'subscriptions' -or (& $text $segments[3]) -ine 'providers') { return $null }
        $subscription = $segments[2]
        if ($subscription.Count -ne 1 -or $subscription[0].Kind -ne 'Member' -or $subscription[0].Name -ine 'subscriptionId' -or
            $subscription[0].Target.Kind -ne 'Call' -or $subscription[0].Target.Name -ine 'subscription' -or @($subscription[0].Target.Arguments).Count -ne 0) { return $null }
        $namespace = & $text $segments[4]
        if ($namespace -notmatch '^[A-Za-z0-9]+(\.[A-Za-z0-9]+)+$') { return $null }
        $types = [System.Collections.Generic.List[string]]::new()
        $names = [System.Collections.Generic.List[string]]::new()
        for ($i = 5; $i -lt $segments.Count; $i += 2) {
            $type = & $text $segments[$i]
            if ($type -notmatch '^[A-Za-z0-9]+$' -or $segments[$i + 1].Count -ne 1) { return $null }
            $name = $segments[$i + 1][0]
            if ($name.Kind -ne 'String' -and -not (& $isString $name)) { return $null }
            $types.Add($type)
            $names.Add((& $write $name))
        }
        "subscriptionResourceId($(ConvertTo-iSOCBicepString -Value "$namespace/$($types -join '/')"), $($names -join ', '))"
    }

    switch ($Node.Kind) {
        'String' { return (ConvertTo-iSOCBicepString -Value $Node.Value) }
        'Number' { return [string]$Node.Value }
        'Member' {
            $location = if ($Symbols.PSObject.Properties['Location']) { $Symbols.Location } else { $null }
            if ($location -and $Node.Name -ieq 'location' -and $Node.Target.Kind -eq 'Call' -and $Node.Target.Name -ieq 'resourceGroup' -and @($Node.Target.Arguments).Count -eq 0) {
                return $location
            }
            return (& $write $Node.Target) + '.' + $Node.Name
        }
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
                # Nested string concats flattened, and neighbouring literals
                # joined, so the string is a run of literals and expressions.
                $flat = [System.Collections.Generic.List[object]]::new()
                $flatten = $null
                $flatten = {
                    param($Items)
                    foreach ($item in $Items) {
                        if ($item.Kind -eq 'Call' -and $item.Name -ieq 'concat' -and (& $isString $item)) { & $flatten @($item.Arguments); continue }
                        if ($item.Kind -eq 'String' -and $flat.Count -gt 0 -and $flat[$flat.Count - 1].Kind -eq 'String') {
                            $flat[$flat.Count - 1] = [pscustomobject]@{ Kind = 'String'; Value = $flat[$flat.Count - 1].Value + $item.Value }
                            continue
                        }
                        $flat.Add($item)
                    }
                }
                & $flatten $arguments
                $resourceId = & $subscriptionResourceIdOf $flat
                if ($resourceId) { return $resourceId }
                $parts = [System.Text.StringBuilder]::new()
                foreach ($item in $flat) {
                    if ($item.Kind -eq 'String') { [void]$parts.Append((ConvertTo-iSOCBicepString -Value $item.Value -Fragment)) }
                    else { [void]$parts.Append('${' + (& $write $item) + '}') }
                }
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

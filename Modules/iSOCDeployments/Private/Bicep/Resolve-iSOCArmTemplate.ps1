#Requires -Version 7.2

<#
.SYNOPSIS
    Reduce an ARM template to what it deploys, so two templates can be
    compared.

.DESCRIPTION
    A JSON playbook and the Bicep compiled from it say the same thing in
    different words: Bicep writes concat() as format(), drops dependsOn
    entries it works out itself, adds metadata._generator and orders keys
    its own way. This evaluates every expression symbolically, so both come
    out the same when they deploy the same resources.

.NOTES
    File:         Modules/iSOCDeployments/Private/Bicep/Resolve-iSOCArmTemplate.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-06
    Version:      0.2.0
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Resolve-iSOCArmTemplate {
    <#
    .SYNOPSIS
        Return the parameters, resources and metadata of a template with
        every expression evaluated symbolically.

    .DESCRIPTION
        - parameters('X') becomes {param:X} (the declared spelling of X);
          variables('X') is replaced by the variable's own resolved value.
        - concat(), format() and json() of a literal are evaluated; resourceGroup() and
          subscription() properties become {rg.location}, {rg.name},
          {sub.id} and so on; resourceId() and subscriptionResourceId()
          become the full id they stand for; true(), false() and null()
          their values. Any other function stays as canonical text in braces,
          with its arguments evaluated, so it compares by meaning but is not
          computed.
        - A [[ escape loses its first bracket.
        - Resources are sorted by type and resolved name; dependsOn becomes a
          sorted list of resolved ids; comments, a Logic App's read-only
          properties.provisioningState and metadata._generator are dropped;
          the template's variables, contentVersion and $schema are not
          returned (variables are already folded into the values that use
          them).
        - Object keys are sorted, so key order does not matter; array order
          does, except dependsOn.
        - A parameter's metadata (its description) is dropped: it documents
          the parameter and deploys nothing.
        - A parameter named in -InlineParameter is replaced by its resolved
          default wherever it is read, and left out of the parameters.

    .PARAMETER Template
        The template: dictionaries (or [pscustomobject]) and arrays.

    .PARAMETER InlineParameter
        Parameters to read as their default value, for a parameter the
        deploy never sets: the Bicep writer's location parameter, which
        defaults to resourceGroup().location, then compares equal to a
        template that reads resourceGroup().location itself. A parameter
        named here that the template does not declare, or that has no
        default, is ignored.

    .OUTPUTS
        [System.Collections.Specialized.OrderedDictionary] parameters,
        resources and metadata.

    .EXAMPLE
        Resolve-iSOCArmTemplate -Template $template | ConvertTo-Json -Depth 100
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [object] $Template,

        [string[]] $InlineParameter = @()
    )

    $entryOf = {
        param($Object, [string] $Name)
        foreach ($entry in Get-iSOCPropertyEntry -InputObject $Object) { if ($entry.Name -ieq $Name) { return $entry.Value } }
        $null
    }
    $isObject = { param($Value) $Value -is [System.Collections.IDictionary] -or $Value -is [System.Management.Automation.PSCustomObject] }

    $parameterNames = @{}
    # The parameters read as their default: name -> the default's raw value.
    $inlined = @{}
    foreach ($entry in Get-iSOCPropertyEntry -InputObject (& $entryOf $Template 'parameters')) {
        $parameterNames[$entry.Name] = $entry.Name
        if (@($InlineParameter | Where-Object { $_ -ieq $entry.Name }).Count -gt 0) {
            $defaultEntry = @(Get-iSOCPropertyEntry -InputObject $entry.Value | Where-Object { $_.Name -ieq 'defaultValue' })
            if ($defaultEntry.Count -gt 0) { $inlined[$entry.Name] = $defaultEntry[0].Value }
        }
    }
    $variableValues = @{}
    foreach ($entry in Get-iSOCPropertyEntry -InputObject (& $entryOf $Template 'variables')) { $variableValues[$entry.Name] = $entry.Value }
    $variableCache = @{}
    $resolving = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $resolveValue = $null
    $evaluate = $null
    $text = { param($Value) if ($Value -is [string]) { $Value } else { ConvertTo-Json -InputObject $Value -Depth 100 -Compress } }
    $idOf = {
        param([string] $Prefix, [string] $Type, [object[]] $Names)
        $segments = @($Type -split '/')
        $path = $segments[0]
        for ($i = 1; $i -lt $segments.Count; $i++) {
            $path += '/' + $segments[$i]
            if ($i - 1 -lt $Names.Count) { $path += '/' + (& $text $Names[$i - 1]) }
        }
        "$Prefix/providers/$path"
    }

    $evaluate = {
        param($Node)
        switch ($Node.Kind) {
            'String' { return $Node.Value }
            'Number' { return $Node.Value }
            'Member' {
                if ($Node.Target.Kind -eq 'Call' -and @($Node.Target.Arguments).Count -eq 0) {
                    $scope = $Node.Target.Name.ToLowerInvariant()
                    $member = $Node.Name.ToLowerInvariant()
                    if ($scope -eq 'resourcegroup') {
                        if ($member -eq 'id') { return '/subscriptions/{sub.id}/resourceGroups/{rg.name}' }
                        return "{rg.$member}"
                    }
                    if ($scope -eq 'subscription') {
                        if ($member -eq 'subscriptionid') { return '{sub.id}' }
                        if ($member -eq 'id') { return '/subscriptions/{sub.id}' }
                        return "{sub.$member}"
                    }
                    if ($scope -in 'tenant', 'deployment', 'environment') { return "{$scope.$member}" }
                }
                $target = & $evaluate $Node.Target
                if (& $isObject $target) { return (& $entryOf $target $Node.Name) }
                return '{' + (& $text $target) + '.' + $Node.Name.ToLowerInvariant() + '}'
            }
            'Index' {
                $target = & $evaluate $Node.Target
                $index = & $evaluate $Node.Index
                if ($target -is [array] -and $index -is [long]) { return , $target[[int]$index] }
                if ((& $isObject $target) -and $index -is [string]) { return (& $entryOf $target $index) }
                return '{' + (& $text $target) + '[' + (& $text $index) + ']}'
            }
        }

        $arguments = @($Node.Arguments | ForEach-Object { , (& $evaluate $_) })
        $name = $Node.Name.ToLowerInvariant()
        switch ($name) {
            'parameters' {
                $key = [string]$arguments[0]
                $declared = if ($parameterNames.ContainsKey($key)) { $parameterNames[$key] } else { $key }
                if ($inlined.ContainsKey($declared)) { return , (& $resolveValue $inlined[$declared]) }
                return "{param:$declared}"
            }
            'variables' {
                $key = [string]$arguments[0]
                if ($variableCache.ContainsKey($key)) { return , $variableCache[$key] }
                if (-not $variableValues.ContainsKey($key)) { return "{variable:$key}" }
                if (-not $resolving.Add($key)) { throw "Variable '$key' refers to itself." }
                $value = & $resolveValue $variableValues[$key]
                [void]$resolving.Remove($key)
                $variableCache[$key] = $value
                return , $value
            }
            'concat' {
                if (@($arguments | Where-Object { $_ -is [array] }).Count -gt 0) { return , @($arguments | ForEach-Object { $_ }) }
                return (($arguments | ForEach-Object { & $text $_ }) -join '')
            }
            'format' {
                $pattern = [string]$arguments[0]
                $builder = [System.Text.StringBuilder]::new()
                for ($i = 0; $i -lt $pattern.Length; $i++) {
                    $character = $pattern[$i]
                    if ($character -eq '{' -and $i + 1 -lt $pattern.Length -and $pattern[$i + 1] -eq '{') { [void]$builder.Append('{'); $i++; continue }
                    if ($character -eq '}' -and $i + 1 -lt $pattern.Length -and $pattern[$i + 1] -eq '}') { [void]$builder.Append('}'); $i++; continue }
                    if ($character -eq '{') {
                        $close = $pattern.IndexOf('}', $i)
                        $slot = $pattern.Substring($i + 1, $close - $i - 1)
                        [void]$builder.Append((& $text $arguments[1 + [int]($slot -split ':')[0]]))
                        $i = $close
                        continue
                    }
                    [void]$builder.Append($character)
                }
                return $builder.ToString()
            }
            'json' { if ($arguments[0] -is [string]) { return , (ConvertFrom-iSOCJsonText -Text $arguments[0]) } }
            'true' { return $true }
            'false' { return $false }
            'null' { return $null }
            'resourceid' {
                $typeAt = -1
                for ($i = 0; $i -lt $arguments.Count; $i++) { if (($arguments[$i] -is [string]) -and $arguments[$i] -match '^[^/{}]+\.[^/{}]+/') { $typeAt = $i; break } }
                if ($typeAt -ge 0 -and $typeAt -le 2) {
                    $subscription = if ($typeAt -eq 2) { & $text $arguments[0] } else { '{sub.id}' }
                    $group = if ($typeAt -ge 1) { & $text $arguments[$typeAt - 1] } else { '{rg.name}' }
                    return (& $idOf "/subscriptions/$subscription/resourceGroups/$group" $arguments[$typeAt] @($arguments | Select-Object -Skip ($typeAt + 1)))
                }
            }
            'subscriptionresourceid' {
                $typeAt = -1
                for ($i = 0; $i -lt $arguments.Count; $i++) { if (($arguments[$i] -is [string]) -and $arguments[$i] -match '^[^/{}]+\.[^/{}]+/') { $typeAt = $i; break } }
                if ($typeAt -ge 0 -and $typeAt -le 1) {
                    $subscription = if ($typeAt -eq 1) { & $text $arguments[0] } else { '{sub.id}' }
                    return (& $idOf "/subscriptions/$subscription" $arguments[$typeAt] @($arguments | Select-Object -Skip ($typeAt + 1)))
                }
            }
        }
        '{' + $name + '(' + ((@($arguments | ForEach-Object { & $text $_ })) -join ',') + ')}'
    }

    $resolveValue = {
        param($Value)
        if ($Value -is [string]) {
            if ($Value.StartsWith('[[')) { return $Value.Substring(1) }
            if ($Value.Length -ge 2 -and $Value.StartsWith('[') -and $Value.EndsWith(']')) {
                return , (& $evaluate (ConvertFrom-iSOCArmExpression -Expression $Value.Substring(1, $Value.Length - 2)))
            }
            return $Value
        }
        if (& $isObject $Value) {
            $sorted = [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::Ordinal)
            foreach ($entry in @(Get-iSOCPropertyEntry -InputObject $Value | Sort-Object Name -CaseSensitive)) { $sorted[$entry.Name] = & $resolveValue $entry.Value }
            return $sorted
        }
        if ($Value -is [System.Collections.IEnumerable]) { return , @($Value | ForEach-Object { , (& $resolveValue $_) }) }
        if ($Value -is [int] -or $Value -is [short]) { return [long]$Value }
        $Value
    }

    $parameters = [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::Ordinal)
    foreach ($entry in @(Get-iSOCPropertyEntry -InputObject (& $entryOf $Template 'parameters') | Sort-Object Name -CaseSensitive)) {
        if ($inlined.ContainsKey($entry.Name)) { continue }
        $definition = & $resolveValue $entry.Value
        foreach ($key in @($definition.Keys | Where-Object { $_ -ieq 'metadata' })) { $definition.Remove($key) }
        $type = & $entryOf $definition 'type'
        if ($type) { $definition['type'] = ([string]$type).ToLowerInvariant() }
        $parameters[$entry.Name] = $definition
    }

    $resources = foreach ($resource in @(& $entryOf $Template 'resources')) {
        $resolved = [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::Ordinal)
        foreach ($entry in @(Get-iSOCPropertyEntry -InputObject $resource | Sort-Object Name -CaseSensitive)) {
            if ($entry.Name -in 'comments', 'dependsOn') { continue }
            $resolved[$entry.Name] = & $resolveValue $entry.Value
        }
        if ([string]$resolved['type'] -ieq 'Microsoft.Logic/workflows' -and $resolved['properties'] -is [System.Collections.IDictionary]) {
            $resolved['properties'].Remove('provisioningState')
        }
        $type = [string]$resolved['type']
        $byId = foreach ($dependency in @(& $entryOf $resource 'dependsOn')) {
            if ($null -eq $dependency) { continue }
            $value = & $resolveValue $dependency
            $value = [string]$value
            if ($value -notmatch '^/subscriptions/') {
                $match = @(@(& $entryOf $Template 'resources') | Where-Object { (& $text (& $resolveValue (& $entryOf $_ 'name'))) -eq $value })
                if ($match.Count -eq 1) { $value = & $idOf '/subscriptions/{sub.id}/resourceGroups/{rg.name}' ([string](& $entryOf $match[0] 'type')) @(([string](& $resolveValue (& $entryOf $match[0] 'name'))) -split '/') }
            }
            $value
        }
        $resolved['dependsOn'] = @($byId | Sort-Object -CaseSensitive)
        [pscustomobject]@{ Key = "$type|$(& $text $resolved['name'])"; Resource = $resolved }
    }
    $sortedResources = @($resources | Sort-Object Key -CaseSensitive | ForEach-Object { $_.Resource })

    $metadata = [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::Ordinal)
    foreach ($entry in @(Get-iSOCPropertyEntry -InputObject (& $entryOf $Template 'metadata') | Sort-Object Name -CaseSensitive)) {
        if ($entry.Name -eq '_generator') { continue }
        $metadata[$entry.Name] = & $resolveValue $entry.Value
    }

    $result = [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::Ordinal)
    $result['parameters'] = $parameters
    $result['resources'] = $sortedResources
    $result['metadata'] = $metadata
    $result
}

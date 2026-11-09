#Requires -Version 7.6

<#
.SYNOPSIS
    Write an ARM template as a Bicep file.

.DESCRIPTION
    The module's own Bicep writer, so exporting a playbook as Bicep needs no
    Bicep CLI. It covers the templates playbooks are made of (parameters,
    variables, resources, metadata) and refuses, with the reason, anything
    it does not write faithfully.

.NOTES
    File:         Modules/iSOCDeployments/Private/Bicep/ConvertTo-iSOCBicepTemplate.ps1
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

function ConvertTo-iSOCBicepTemplate {
    <#
    .SYNOPSIS
        Return the .bicep text for an ARM template.

    .DESCRIPTION
        In order:

        - a metadata statement for each template metadata entry;
        - a param for each parameter, under its ARM name (the deploy fills
          parameters by name), with its type, default and @allowed,
          @description, @minLength, @maxLength, @minValue and @maxValue
          decorators, and @secure() for securestring and secureObject. A
          parameter without a description of its own gets the one
          -ParameterDescription gives it, if any. Parameters with
          decorators are set apart by blank lines;
        - a location parameter, defaulting to resourceGroup().location,
          when an expression reads resourceGroup().location and the
          template has no location parameter; every such read then uses
          the parameter. The deploy never sets it, so the deployment is the
          same;
        - a var for each variable, named in lower camel case
          (ConvertTo-iSOCBicepCamelCase) unless -VariableName gives the name;
        - a resource for each resource, with a symbolic name (workflow for
          a Logic App; a connection's from its name variable, so
          microsoftSentinelConnectionName gives microsoftSentinelConnection).
          The resource keeps name, location, kind, sku, plan, tags,
          identity, zones and properties, in that order. A dependsOn entry is
          written only when the resource does not already refer to the
          resource it names, since Bicep adds those itself. comments become
          a // line. A Logic App's read-only properties.provisioningState is
          left out. Where Bicep's type data for a playbook resource type is
          known to be wrong or missing (no types for Logic Apps 2017-07-01;
          kind and parameterValueType missing from API connections
          2016-06-01), a #disable-next-line for that warning code goes on
          the line before, so the file builds without warnings.

        The template's contentVersion is not kept, as Bicep always compiles
        to 1.0.0.0. Outputs, functions, a copy loop, a condition, child
        resources, a scope, a nested deployment, a parameter or metadata
        name that is not an identifier, a template for another deployment
        scope, and a dependsOn entry outside the template all throw, naming
        what was found.

        The text uses LF line endings and ends with one line feed.

    .PARAMETER Template
        The template: dictionaries (or [pscustomobject]) as ConvertFrom-Json,
        ConvertFrom-iSOCJsonText or ConvertTo-iSOCPlaybookTemplate give it.

    .PARAMETER VariableName
        Bicep names for variables, keyed by their ARM names. A variable not
        named here is written in lower camel case. Clashes and keywords
        still get a number.

    .PARAMETER ParameterDescription
        Descriptions for parameters that have none of their own, keyed by
        parameter name.

    .OUTPUTS
        [string] The Bicep file's text.

    .EXAMPLE
        ConvertTo-iSOCBicepTemplate -Template (ConvertFrom-iSOCJsonText -Text (Get-Content $path -Raw))
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [object] $Template,

        [hashtable] $VariableName = @{},

        [hashtable] $ParameterDescription = @{}
    )

    $entriesOf = {
        param($Object)
        foreach ($entry in Get-iSOCPropertyEntry -InputObject $Object) { [pscustomobject]@{ Key = $entry.Name; Value = $entry.Value } }
    }
    $get = {
        param($Object, [string] $Key)
        foreach ($entry in & $entriesOf $Object) { if ($entry.Key -ieq $Key) { return $entry.Value } }
        $null
    }
    $isEmpty = {
        param($Value)
        if ($null -eq $Value) { return $true }
        if ($Value -is [System.Collections.IDictionary] -or $Value -is [System.Management.Automation.PSCustomObject]) { return @(& $entriesOf $Value).Count -eq 0 }
        if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) { return @($Value).Count -eq 0 }
        $false
    }
    $isIdentifier = { param([string] $Name) $Name -match '^[A-Za-z_][A-Za-z0-9_]*$' }
    $isExpression = { param($Value) $Value -is [string] -and $Value.Length -ge 2 -and $Value.StartsWith('[') -and $Value.EndsWith(']') -and -not $Value.StartsWith('[[') }
    $nameTextOf = {
        param($Value)
        if (& $isExpression $Value) { return ConvertTo-iSOCArmExpressionText -Node (ConvertFrom-iSOCArmExpression -Expression $Value.Substring(1, $Value.Length - 2)) }
        ConvertTo-iSOCArmExpressionText -Node ([pscustomobject]@{ Kind = 'String'; Value = [string]$Value })
    }

    foreach ($entry in & $entriesOf $Template) {
        $key = $entry.Key
        if ($key -in '$schema', 'contentVersion', 'metadata', 'parameters', 'variables', 'resources') { continue }
        if ($key -in 'outputs', 'functions' -and (& $isEmpty $entry.Value)) { continue }
        throw "The template's '$key' is not written as Bicep; only metadata, parameters, variables and resources are."
    }
    $schema = [string](& $get $Template '$schema')
    if ($schema -and $schema -notmatch '/deploymentTemplate\.json#?$') { throw "The template is for another deployment scope ($schema); only resource group templates are written as Bicep." }

    $taken = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $symbols = [pscustomobject]@{
        Parameters     = @{}
        ParameterTypes = @{}
        Variables      = @{}
        VariableValues = @{}
        Resources      = [System.Collections.Generic.List[object]]::new()
        Current        = $null
        Location       = $null
    }

    $parameters = @(& $entriesOf (& $get $Template 'parameters'))
    foreach ($parameter in $parameters) {
        if (-not (& $isIdentifier $parameter.Key)) { throw "Parameter '$($parameter.Key)' is not a Bicep identifier, and renaming it would change what the deploy fills in." }
        [void]$taken.Add($parameter.Key)
        $symbols.Parameters[$parameter.Key] = $parameter.Key
        $symbols.ParameterTypes[$parameter.Key] = ([string](& $get $parameter.Value 'type')).ToLowerInvariant()
    }

    # Whether an expression in the variables or resources reads
    # resourceGroup().location. If one does and the template has no location
    # parameter, the file gets one, defaulting to it, and every use reads the
    # parameter instead, as Bicep's linter asks.
    $readsLocation = $null
    $readsLocation = {
        param($Value)
        if ($Value -is [string]) { return ((& $isExpression $Value) -and $Value -match '(?i)\bresourceGroup\(\s*\)\.location\b') }
        if ($Value -is [System.Collections.IDictionary] -or $Value -is [System.Management.Automation.PSCustomObject]) {
            foreach ($entry in & $entriesOf $Value) { if (& $readsLocation $entry.Value) { return $true } }
            return $false
        }
        if ($Value -is [System.Collections.IEnumerable]) {
            foreach ($item in $Value) { if (& $readsLocation $item) { return $true } }
        }
        $false
    }
    $locationParameter = $null
    if (-not @($parameters | Where-Object { $_.Key -ieq 'location' }).Count -and
        ((& $readsLocation (& $get $Template 'variables')) -or (& $readsLocation @(& $get $Template 'resources')))) {
        $locationParameter = 'location'
        [void]$taken.Add($locationParameter)
    }

    $variables = @(& $entriesOf (& $get $Template 'variables'))
    foreach ($variable in $variables) {
        if ($variable.Key -ieq 'copy') { throw 'Variable copy loops are not written as Bicep.' }
        $preferred = if ($VariableName.ContainsKey($variable.Key)) { [string]$VariableName[$variable.Key] } else { ConvertTo-iSOCBicepCamelCase -Name $variable.Key }
        $symbols.Variables[$variable.Key] = Get-iSOCBicepIdentifier -Name $preferred -Taken $taken
        $symbols.VariableValues[$variable.Key] = $variable.Value
    }

    $resources = @(& $get $Template 'resources')
    $allowedKeys = 'type', 'apiVersion', 'name', 'location', 'kind', 'sku', 'plan', 'tags', 'identity', 'zones', 'properties', 'dependsOn', 'comments'
    foreach ($resource in $resources) {
        foreach ($entry in & $entriesOf $resource) {
            if ($entry.Key -notin $allowedKeys) { throw "Resource '$(& $get $resource 'name')' has '$($entry.Key)', which is not written as Bicep." }
        }
        $type = [string](& $get $resource 'type')
        $name = & $get $resource 'name'
        if (-not $type -or -not (& $get $resource 'apiVersion') -or $null -eq $name) { throw 'Every resource needs a type, an apiVersion and a name.' }
        if ($type -ieq 'Microsoft.Resources/deployments') { throw "Nested deployments ('$name') are not written as Bicep." }
        $base = switch -Regex ($type) {
            '^Microsoft\.Logic/workflows$' { 'workflow'; break }
            '^Microsoft\.Web/connections$' {
                if ((& $isExpression $name) -and $name -match "^\[variables\('([^']+)'\)\]$") {
                    $nameVariable = $Matches[1]
                    $stem = if ($symbols.Variables.ContainsKey($nameVariable)) { $symbols.Variables[$nameVariable] } else { ConvertTo-iSOCBicepCamelCase -Name $nameVariable }
                    $stem -replace 'Name$', ''
                }
                else { 'connection' }
                break
            }
            default { $segment = ($type -split '/')[-1]; $segment.Substring(0, 1).ToLowerInvariant() + $segment.Substring(1) -replace 's$', '' }
        }
        $symbols.Resources.Add([pscustomobject]@{
                Type     = $type
                NameText = & $nameTextOf $name
                Symbol   = Get-iSOCBicepIdentifier -Name $base -Taken $taken
                Resource = $resource
            })
    }

    $blocks = [System.Collections.Generic.List[string]]::new()

    $metadataLines = foreach ($entry in & $entriesOf (& $get $Template 'metadata')) {
        if ($entry.Key -eq '_generator') { continue }
        if (-not (& $isIdentifier $entry.Key)) { throw "Metadata '$($entry.Key)' is not a Bicep identifier." }
        "metadata $($entry.Key) = $(ConvertTo-iSOCBicepValue -Value $entry.Value -Symbols $symbols)"
    }
    if (@($metadataLines).Count -gt 0) { $blocks.Add(($metadataLines -join "`n")) }

    $typeNames = @{ string = 'string'; securestring = 'string'; int = 'int'; bool = 'bool'; object = 'object'; secureobject = 'object'; array = 'array' }
    $parameterLines = foreach ($parameter in $parameters) {
        $definition = $parameter.Value
        $armType = $symbols.ParameterTypes[$parameter.Key]
        if (-not $typeNames.ContainsKey($armType)) { throw "Parameter '$($parameter.Key)' has type '$armType', which is not written as Bicep." }
        $decorators = [System.Collections.Generic.List[string]]::new()
        $described = $false
        foreach ($entry in & $entriesOf $definition) {
            switch ($entry.Key) {
                'type' { }
                'defaultValue' { }
                'allowedValues' { $decorators.Add("@allowed($(ConvertTo-iSOCBicepValue -Value @($entry.Value) -Symbols $symbols))") }
                'minLength' { $decorators.Add("@minLength($($entry.Value))") }
                'maxLength' { $decorators.Add("@maxLength($($entry.Value))") }
                'minValue' { $decorators.Add("@minValue($($entry.Value))") }
                'maxValue' { $decorators.Add("@maxValue($($entry.Value))") }
                'metadata' {
                    foreach ($meta in & $entriesOf $entry.Value) {
                        if ($meta.Key -ieq 'description') {
                            $decorators.Add("@description($(ConvertTo-iSOCBicepString -Value ([string]$meta.Value)))")
                            $described = $true
                        }
                        else { throw "Parameter '$($parameter.Key)' has metadata '$($meta.Key)', which is not written as Bicep." }
                    }
                }
                default { throw "Parameter '$($parameter.Key)' has '$($entry.Key)', which is not written as Bicep." }
            }
        }
        if ($armType -in 'securestring', 'secureobject') { $decorators.Insert(0, '@secure()') }
        if (-not $described -and $ParameterDescription.ContainsKey($parameter.Key)) {
            $decorators.Insert(0, "@description($(ConvertTo-iSOCBicepString -Value ([string]$ParameterDescription[$parameter.Key])))")
        }
        $line = "param $($parameter.Key) $($typeNames[$armType])"
        $default = @(& $entriesOf $definition | Where-Object { $_.Key -ieq 'defaultValue' })
        if ($default.Count -gt 0) { $line += " = $(ConvertTo-iSOCBicepValue -Value $default[0].Value -Symbols $symbols)" }
        (@($decorators) + $line) -join "`n"
    }
    if ($locationParameter) {
        $parameterLines = @($parameterLines | Where-Object { $_ }) + (
            "@description($(ConvertTo-iSOCBicepString -Value "The region for the resources; the resource group's by default."))`n" +
            "param $locationParameter string = resourceGroup().location")
    }
    # Parameters with decorators are set apart by a blank line, so each
    # decorator reads with its own parameter.
    $parameterSeparator = if (@($parameterLines | Where-Object { $_.Contains("`n") }).Count -gt 0) { "`n`n" } else { "`n" }
    if (@($parameterLines).Count -gt 0) { $blocks.Add(($parameterLines -join $parameterSeparator)) }
    # Defaults are written first, with resourceGroup().location as it is;
    # from here on it is the location parameter.
    $symbols.Location = $locationParameter

    $variableLines = foreach ($variable in $variables) {
        "var $($symbols.Variables[$variable.Key]) = $(ConvertTo-iSOCBicepValue -Value $variable.Value -Symbols $symbols)"
    }
    if (@($variableLines).Count -gt 0) { $blocks.Add(($variableLines -join "`n")) }

    # Where Bicep's own type data for the playbook resource types is wrong
    # or missing, so a correct template still compiles with a warning. Each
    # gap gets a #disable-next-line for its code, on the line it is reported
    # on, so a playbook builds clean. Keys are type@apiVersion in lower case.
    $typeGaps = @{
        # No type data at all for this api-version.
        'microsoft.logic/workflows@2017-07-01'  = @{ Resource = 'BCP081' }
        # kind (V1) and properties.parameterValueType (Alternative, for a
        # managed identity connection) are valid but not in the type data.
        'microsoft.web/connections@2016-06-01' = @{ Lines = @{ '  kind: ' = 'BCP187'; '    parameterValueType: ' = 'BCP037' } }
    }

    $order = 'name', 'location', 'kind', 'sku', 'plan', 'tags', 'identity', 'zones', 'properties'
    foreach ($entry in $symbols.Resources) {
        $resource = $entry.Resource
        $symbols.Current = $entry.Symbol
        $gap = $typeGaps["$($entry.Type)@$(& $get $resource 'apiVersion')".ToLowerInvariant()]
        $bodyLines = [System.Collections.Generic.List[string]]::new()
        foreach ($key in $order) {
            $present = @(& $entriesOf $resource | Where-Object { $_.Key -ieq $key })
            if ($present.Count -eq 0) { continue }
            $value = $present[0].Value
            if ($key -eq 'properties' -and $entry.Type -ieq 'Microsoft.Logic/workflows') {
                $kept = [ordered]@{}
                foreach ($property in & $entriesOf $value) { if ($property.Key -ne 'provisioningState') { $kept[$property.Key] = $property.Value } }
                $value = $kept
            }
            $bodyLines.Add("  ${key}: $(ConvertTo-iSOCBicepValue -Value $value -Symbols $symbols -Depth 1)")
        }

        $body = $bodyLines -join "`n"
        if ($gap -and $gap.ContainsKey('Lines')) {
            foreach ($start in $gap['Lines'].Keys) {
                $indent = $start.Substring(0, $start.Length - $start.TrimStart().Length)
                $code = $gap['Lines'][$start]
                $body = [regex]::Replace($body, "(?m)^$([regex]::Escape($start))", "$indent#disable-next-line $code`n$start")
            }
        }
        $explicit = foreach ($dependency in @(& $get $resource 'dependsOn')) {
            if ($null -eq $dependency) { continue }
            $text = if (& $isExpression $dependency) {
                $node = ConvertFrom-iSOCArmExpression -Expression $dependency.Substring(1, $dependency.Length - 2)
                if ($node.Kind -ne 'Call' -or $node.Name -ine 'resourceId' -or @($node.Arguments).Count -ne 2 -or $node.Arguments[0].Kind -ne 'String') {
                    throw "Resource '$($entry.Symbol)' depends on '$dependency', which is not a resource in the template."
                }
                @{ Type = $node.Arguments[0].Value; NameText = ConvertTo-iSOCArmExpressionText -Node $node.Arguments[1] }
            }
            else { @{ Type = $null; NameText = & $nameTextOf $dependency } }
            $target = @($symbols.Resources | Where-Object { $_.NameText -ieq $text.NameText -and (-not $text.Type -or $_.Type -ieq $text.Type) })
            if ($target.Count -ne 1) { throw "Resource '$($entry.Symbol)' depends on '$dependency', which is not a resource in the template." }
            if ($body -notmatch "(?<![A-Za-z0-9_])$([regex]::Escape($target[0].Symbol))\.") { $target[0].Symbol }
        }
        if (@($explicit).Count -gt 0) { $body += "`n  dependsOn: [`n" + ((@($explicit) | ForEach-Object { "    $_" }) -join "`n") + "`n  ]" }

        $comment = [string](& $get $resource 'comments')
        $header = if ($comment) { (($comment -split "`r?`n") | ForEach-Object { "// $_" }) -join "`n" } else { $null }
        $declaration = "resource $($entry.Symbol) '$($entry.Type)@$(& $get $resource 'apiVersion')' = {`n$body`n}"
        if ($gap -and $gap.ContainsKey('Resource')) { $declaration = "#disable-next-line $($gap['Resource'])`n$declaration" }
        $blocks.Add($(if ($header) { "$header`n$declaration" } else { $declaration }))
    }
    $symbols.Current = $null

    ($blocks -join "`n`n") + "`n"
}

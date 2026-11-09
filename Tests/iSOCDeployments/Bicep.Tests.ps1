#Requires -Version 7.6
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    Pester tests for the module's Bicep writer, the ARM template
    comparison and the Bicep CLI wrapper.

.DESCRIPTION
    - ConvertFrom-iSOCJsonText: dates stay text, order and case kept.
    - The ARM expression parser and its canonical text.
    - Bicep strings (every escape, ''' blocks), identifiers, camel case,
      expressions (parameters, variables, interpolation, symbolic
      references, subscriptionResourceId, the location parameter,
      operators, function spelling) and whole templates (names chosen by
      the caller, descriptions), against exact expected text, and what the
      writer refuses.
    - Resolve-iSOCArmTemplate and Compare-iSOCArmTemplate: what counts as
      the same deployment (descriptions do not count; an inlined location
      parameter reads as resourceGroup().location) and how a difference is
      reported.
    - Invoke-iSOCBicep and round trips through the real Bicep CLI: the
      fixture playbooks and a template with every awkward value are
      written as Bicep, compiled, and must deploy the same thing as the
      JSON they came from. These need the Bicep CLI on the PATH, as the
      module does for Bicep playbooks.

.EXAMPLE
    Invoke-Pester -Path Tests/iSOCDeployments/Bicep.Tests.ps1

    Runs the whole suite.

.NOTES
    File:         Tests/iSOCDeployments/Bicep.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-06
    Version:      0.2.1
    Last Updated: 2026-11-09
    Requires:     PowerShell 7.6+, Pester 5+, the Bicep CLI
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $script:repoRoot 'Modules/iSOCDeployments/iSOCDeployments.psd1') -Force
    $script:fixturePlaybooks = Join-Path $PSScriptRoot 'Fixtures/repo/Content/Playbooks'

    function Invoke-InModule {
        param([scriptblock] $ScriptBlock, [hashtable] $Parameters = @{})
        InModuleScope iSOCDeployments -ScriptBlock $ScriptBlock -Parameters $Parameters
    }
    function Get-SymbolTable {
        param([hashtable] $Parameters = @{}, [hashtable] $Variables = @{}, [object[]] $Resources = @(), [string] $Current, [string] $Location)
        $symbols = [pscustomobject]@{ Parameters = @{}; ParameterTypes = @{}; Variables = @{}; VariableValues = @{}; Resources = [System.Collections.Generic.List[object]]::new(); Current = $Current; Location = $(if ($Location) { $Location } else { $null }) }
        foreach ($name in $Parameters.Keys) { $symbols.Parameters[$name] = $name; $symbols.ParameterTypes[$name] = $Parameters[$name] }
        foreach ($name in $Variables.Keys) { $symbols.Variables[$name] = $Variables[$name].Identifier; $symbols.VariableValues[$name] = $Variables[$name].Value }
        foreach ($resource in $Resources) { $symbols.Resources.Add($resource) }
        $symbols
    }
    function ConvertTo-Bicep {
        param([string] $Expression, [psobject] $Symbols)
        Invoke-InModule { param($E, $S) ConvertTo-iSOCBicepExpression -Node (ConvertFrom-iSOCArmExpression -Expression $E) -Symbols $S } @{ E = $Expression; S = $Symbols }
    }
    function ConvertTo-BicepFile {
        param([string] $Json, [hashtable] $VariableName = @{}, [hashtable] $ParameterDescription = @{})
        Invoke-InModule { param($J, $V, $D) ConvertTo-iSOCBicepTemplate -Template (ConvertFrom-iSOCJsonText -Text $J) -VariableName $V -ParameterDescription $D } @{ J = $Json; V = $VariableName; D = $ParameterDescription }
    }
    function Compare-Json {
        param([string] $Expected, [string] $Actual, [string[]] $InlineParameter = @())
        Invoke-InModule { param($A, $B, $I) Compare-iSOCArmTemplate -Expected (ConvertFrom-iSOCJsonText -Text $A) -Actual (ConvertFrom-iSOCJsonText -Text $B) -InlineParameter $I } @{ A = $Expected; B = $Actual; I = $InlineParameter }
    }

    # A JSON template written as Bicep beside it in TestDrive, compiled, and
    # compared with the JSON: nothing when they deploy the same thing. The
    # location parameter the writer adds reads as resourceGroup().location.
    function Test-RoundTrip {
        param([string[]] $JsonPath)
        $folder = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $folder | Out-Null
        $pairs = foreach ($path in $JsonPath) {
            $bicep = Join-Path $folder ([System.IO.Path]::GetFileNameWithoutExtension($path) + '.bicep')
            [System.IO.File]::WriteAllText($bicep, (ConvertTo-BicepFile -Json (Get-Content -LiteralPath $path -Raw)))
            [pscustomobject]@{ Json = $path; Bicep = $bicep }
        }
        $builds = @(Invoke-InModule { param($P) Invoke-iSOCBicep -Path $P } @{ P = @($pairs | ForEach-Object { $_.Bicep }) })
        for ($i = 0; $i -lt $builds.Count; $i++) {
            if (-not $builds[$i].Succeeded) { "$($pairs[$i].Json): $($builds[$i].Errors -join ' ')"; continue }
            $json = Get-Content -LiteralPath $pairs[$i].Json -Raw
            $declared = @((ConvertFrom-Json -InputObject $json).parameters.PSObject.Properties.Name)
            $inline = if ($declared -notcontains 'location') { @('location') } else { @() }
            $difference = Compare-Json -Expected $json -Actual $builds[$i].Json -InlineParameter $inline
            if ($difference) { "$($pairs[$i].Json): $difference" }
        }
    }
}

AfterAll {
    Remove-Module iSOCDeployments -ErrorAction SilentlyContinue
}

Describe 'ConvertFrom-iSOCJsonText' {
    It 'keeps a date as the text it was' {
        (Invoke-InModule { (ConvertFrom-iSOCJsonText -Text '{"startTime":"2026-01-02T03:04:05Z"}').startTime }) | Should -BeExactly '2026-01-02T03:04:05Z'
    }

    It 'keeps key order and case, a one-item array as an array, and each kind of value' {
        $value = Invoke-InModule { ConvertFrom-iSOCJsonText -Text '{"b":1,"a":[true],"A":null,"c":1.5,"d":{}}' }
        @($value.Keys) | Should -Be @('b', 'a', 'A', 'c', 'd')
        $value['b'] | Should -BeOfType [long]
        , $value['a'] | Should -BeOfType [object[]]
        $value['a'][0] | Should -BeTrue
        $value['A'] | Should -BeNullOrEmpty
        $value['c'] | Should -BeOfType [double]
        $value['d'] | Should -BeOfType [System.Collections.Specialized.OrderedDictionary]
    }
}

Describe 'ConvertFrom-iSOCArmExpression' {
    It 'reads <Case>' -ForEach @(
        @{ Case = 'a doubled quote'; Expression = "'it''s'"; Text = "'it''s'" }
        @{ Case = 'nested calls with spacing'; Expression = "concat( 'a' , parameters( 'B' ) )"; Text = "concat('a',parameters('B'))" }
        @{ Case = 'a member of a call'; Expression = 'resourceGroup().location'; Text = 'resourcegroup().location' }
        @{ Case = 'an index and a negative number'; Expression = "variables('list')[-1]"; Text = "variables('list')[-1]" }
    ) {
        Invoke-InModule { param($E) ConvertTo-iSOCArmExpressionText -Node (ConvertFrom-iSOCArmExpression -Expression $E) } @{ E = $Expression } | Should -BeExactly $Text
    }

    It 'refuses <Case>' -ForEach @(
        @{ Case = 'an unterminated string'; Expression = "concat('a" }
        @{ Case = 'text after the expression'; Expression = "parameters('a') extra" }
        @{ Case = 'a missing bracket'; Expression = "variables('a'" }
        @{ Case = 'a bare word'; Expression = 'location' }
    ) {
        { Invoke-InModule { param($E) ConvertFrom-iSOCArmExpression -Expression $E } @{ E = $Expression } } | Should -Throw '*Cannot read the ARM expression*'
    }
}

Describe 'ConvertTo-iSOCBicepString' {
    It 'escapes <Case>' -ForEach @(
        @{ Case = 'a quote'; Value = "it's"; Expected = "'it\'s'" }
        @{ Case = 'a backslash'; Value = 'a\b'; Expected = "'a\\b'" }
        @{ Case = 'interpolation'; Value = 'cost ${x} $y'; Expected = "'cost \`${x} `$y'" }
        @{ Case = 'line breaks and tabs'; Value = "a`r`nb`tc"; Expected = "'a\r\nb\tc'" }
        @{ Case = 'another control character'; Value = "a$([char]1)b"; Expected = "'a\u{1}b'" }
    ) {
        Invoke-InModule { param($V) ConvertTo-iSOCBicepString -Value $V } @{ V = $Value } | Should -BeExactly $Expected
    }

    It 'writes multi-line text as a verbatim block when it can' {
        Invoke-InModule { ConvertTo-iSOCBicepString -Value "line 1`n  it's `${not} interpolated`n" -AllowMultiLine } |
            Should -BeExactly "'''`nline 1`n  it's `${not} interpolated`n'''"
    }

    It 'keeps <Case> single-quoted even when multi-line' -ForEach @(
        @{ Case = 'a carriage return'; Value = "a`r`nb" }
        @{ Case = 'text ending in a quote'; Value = "a`nb'" }
        @{ Case = 'three quotes'; Value = "a`n'''b" }
    ) {
        Invoke-InModule { param($V) ConvertTo-iSOCBicepString -Value $V -AllowMultiLine } @{ V = $Value } | Should -Not -BeLike "'''*"
    }

    It 'returns a fragment without quotes' {
        Invoke-InModule { ConvertTo-iSOCBicepString -Value "a'b" -Fragment } | Should -BeExactly "a\'b"
    }
}

Describe 'Get-iSOCBicepIdentifier' {
    It 'makes names into unique identifiers' {
        $names = Invoke-InModule {
            $taken = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($name in 'office365-1', '2nd', 'resource', 'Workflow', 'workflow', 'a.b c') { Get-iSOCBicepIdentifier -Name $name -Taken $taken }
        }
        @($names) | Should -Be @('office365_1', '_2nd', 'resource2', 'Workflow', 'workflow2', 'a_b_c')
    }
}

Describe 'ConvertTo-iSOCBicepCamelCase' {
    It 'writes <Name> as <Expected>' -ForEach @(
        @{ Name = 'MicrosoftSentinelConnectionName'; Expected = 'microsoftSentinelConnectionName' }
        @{ Name = 'VTEnrichment'; Expected = 'vtEnrichment' }
        @{ Name = 'ARMId'; Expected = 'armId' }
        @{ Name = 'URL'; Expected = 'url' }
        @{ Name = 'VT2Report'; Expected = 'vt2Report' }
        @{ Name = 'office365-ConnectionName'; Expected = 'office365-ConnectionName' }
        @{ Name = '_x'; Expected = '_x' }
    ) {
        Invoke-InModule { param($N) ConvertTo-iSOCBicepCamelCase -Name $N } @{ N = $Name } | Should -BeExactly $Expected
    }
}

Describe 'ConvertTo-iSOCBicepExpression' {
    BeforeAll {
        $script:symbols = Get-SymbolTable -Parameters @{ PlaybookName = 'string'; Count = 'int' } -Variables @{
            'conn-Name' = @{ Identifier = 'conn_Name'; Value = "[concat('a-', parameters('PlaybookName'))]" }
            settings    = @{ Identifier = 'settings'; Value = @{ a = 1 } }
        } -Resources @([pscustomobject]@{ Type = 'Microsoft.Web/connections'; NameText = "variables('conn-name')"; Symbol = 'connection' })
    }

    It 'writes <Case>' -ForEach @(
        @{ Case = 'a parameter'; Expression = "parameters('playbookname')"; Expected = 'PlaybookName' }
        @{ Case = 'a renamed variable'; Expression = "variables('conn-Name')"; Expected = 'conn_Name' }
        @{ Case = 'concat with a literal as interpolation'; Expression = "concat('/x/', parameters('PlaybookName'), '/y')"; Expected = "'/x/`${PlaybookName}/y'" }
        @{ Case = 'concat of strings as interpolation'; Expression = "concat(subscription().subscriptionId, variables('conn-Name'))"; Expected = "'`${subscription().subscriptionId}`${conn_Name}'" }
        @{ Case = 'nested concat flattened'; Expression = "concat('a', concat('b', parameters('PlaybookName')))"; Expected = "'ab`${PlaybookName}'" }
        @{ Case = 'concat it cannot type'; Expression = "concat(variables('settings'), parameters('Count'))"; Expected = 'concat(settings, Count)' }
        @{ Case = 'a literal with escapes'; Expression = "concat('it''s ', '`${x}')"; Expected = "'it\'s \`${x}'" }
        @{ Case = 'a template resource id'; Expression = "resourceId('Microsoft.Web/connections', variables('conn-Name'))"; Expected = 'connection.id' }
        @{ Case = 'another resource id'; Expression = "resourceId('Microsoft.Logic/workflows', 'other')"; Expected = "resourceId('Microsoft.Logic/workflows', 'other')" }
        @{ Case = 'operators'; Expression = "if(equals(parameters('Count'), 1), not(true()), and(false(), or(true(), false())))"; Expected = '((Count == 1) ? !(true) : (false && (true || false)))' }
        @{ Case = 'literals'; Expression = "createObject('a', createArray(1, 2), 'b-c', null())"; Expected = "{ a: [1, 2], 'b-c': null }" }
        @{ Case = 'function spelling'; Expression = "uniquestring(resourcegroup().id)"; Expected = 'uniqueString(resourceGroup().id)' }
        @{ Case = 'an index'; Expression = "variables('settings')['a']"; Expected = "settings['a']" }
        @{ Case = 'a subscription-level id'; Expression = "concat('/subscriptions/', subscription().subscriptionId, '/providers/Microsoft.Web/locations/', resourceGroup().location, '/managedApis/office365')"; Expected = "subscriptionResourceId('Microsoft.Web/locations/managedApis', resourceGroup().location, 'office365')" }
        @{ Case = 'a subscription-level id split over literals'; Expression = "concat('/subscriptions/', subscription().subscriptionId, '/providers/', 'Microsoft.Web/locations/westus/managedApis/', parameters('PlaybookName'))"; Expected = "subscriptionResourceId('Microsoft.Web/locations/managedApis', 'westus', PlaybookName)" }
        @{ Case = 'a resource group id as a string'; Expression = "concat('/subscriptions/', subscription().subscriptionId, '/resourceGroups/rg/providers/Microsoft.Logic/workflows/Module-A')"; Expected = "'/subscriptions/`${subscription().subscriptionId}/resourceGroups/rg/providers/Microsoft.Logic/workflows/Module-A'" }
        @{ Case = 'an id with a trailing slash as a string'; Expression = "concat('/subscriptions/', subscription().subscriptionId, '/providers/Microsoft.Web/locations/x/')"; Expected = "'/subscriptions/`${subscription().subscriptionId}/providers/Microsoft.Web/locations/x/'" }
        @{ Case = 'resourceGroup().location without a location parameter'; Expression = 'resourceGroup().location'; Expected = 'resourceGroup().location' }
    ) {
        ConvertTo-Bicep -Expression $Expression -Symbols $script:symbols | Should -BeExactly $Expected
    }

    It 'reads resourceGroup().location as the location parameter, in <Case>' -ForEach @(
        @{ Case = 'a value'; Expression = 'resourceGroup().location'; Expected = 'location' }
        @{ Case = 'interpolation'; Expression = "concat('at-', resourceGroup().location)"; Expected = "'at-`${location}'" }
        @{ Case = 'an id'; Expression = "concat('/subscriptions/', subscription().subscriptionId, '/providers/Microsoft.Web/locations/', resourceGroup().location, '/managedApis/teams')"; Expected = "subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'teams')" }
        @{ Case = 'another property'; Expression = 'resourceGroup().name'; Expected = 'resourceGroup().name' }
    ) {
        $located = Get-SymbolTable -Parameters @{ PlaybookName = 'string' } -Location 'location'
        ConvertTo-Bicep -Expression $Expression -Symbols $located | Should -BeExactly $Expected
    }

    It 'keeps resourceId inside the resource it names' {
        $own = Get-SymbolTable -Variables @{ 'conn-Name' = @{ Identifier = 'conn_Name'; Value = 'x' } } -Resources @([pscustomobject]@{ Type = 'Microsoft.Web/connections'; NameText = "variables('conn-name')"; Symbol = 'connection' }) -Current 'connection'
        ConvertTo-Bicep -Expression "resourceId('Microsoft.Web/connections', variables('conn-Name'))" -Symbols $own | Should -BeExactly "resourceId('Microsoft.Web/connections', conn_Name)"
    }

    It 'refuses a <Kind> the template does not declare' -ForEach @(
        @{ Kind = 'parameter'; Expression = "parameters('Missing')" }
        @{ Kind = 'variable'; Expression = "variables('Missing')" }
    ) {
        { ConvertTo-Bicep -Expression $Expression -Symbols $script:symbols } | Should -Throw "*does not declare*"
    }
}

Describe 'ConvertTo-iSOCBicepTemplate' {
    BeforeAll {
        $script:template = @'
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "metadata": { "title": "T", "tags": ["Module"] },
  "parameters": {
    "PlaybookName": { "defaultValue": "Module-T", "type": "string" },
    "Secret": { "type": "securestring", "metadata": { "description": "A key" } }
  },
  "variables": { "office365-ConnectionName": "[concat('office365-', parameters('PlaybookName'))]" },
  "resources": [
    {
      "type": "Microsoft.Logic/workflows", "apiVersion": "2017-07-01", "name": "[parameters('PlaybookName')]", "location": "[resourceGroup().location]",
      "properties": {
        "provisioningState": "Succeeded", "state": "Enabled",
        "definition": { "$schema": "x", "actions": {}, "triggers": {} },
        "parameters": { "$connections": { "value": { "office365": { "connectionId": "[resourceId('Microsoft.Web/connections', variables('office365-ConnectionName'))]" } } } }
      },
      "dependsOn": [ "[resourceId('Microsoft.Web/connections', variables('office365-ConnectionName'))]" ]
    },
    {
      "type": "Microsoft.Web/connections", "apiVersion": "2016-06-01", "name": "[variables('office365-ConnectionName')]", "location": "[resourceGroup().location]", "kind": "V1",
      "properties": {
        "displayName": "[variables('office365-ConnectionName')]", "parameterValueType": "Alternative",
        "api": { "id": "[concat('/subscriptions/', subscription().subscriptionId, '/providers/Microsoft.Web/locations/', resourceGroup().location, '/managedApis/office365')]" }
      }
    }
  ]
}
'@
    }

    It 'writes metadata, parameters, variables and resources, with symbolic references and the known type gaps' {
        $expected = @'
metadata title = 'T'
metadata tags = [
  'Module'
]

param PlaybookName string = 'Module-T'

@secure()
@description('A key')
param Secret string

@description('The region for the resources; the resource group\'s by default.')
param location string = resourceGroup().location

var office365_ConnectionName = 'office365-${PlaybookName}'

#disable-next-line BCP081
resource workflow 'Microsoft.Logic/workflows@2017-07-01' = {
  name: PlaybookName
  location: location
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'x'
      actions: {}
      triggers: {}
    }
    parameters: {
      '$connections': {
        value: {
          office365: {
            connectionId: office365_Connection.id
          }
        }
      }
    }
  }
}

resource office365_Connection 'Microsoft.Web/connections@2016-06-01' = {
  name: office365_ConnectionName
  location: location
  #disable-next-line BCP187
  kind: 'V1'
  properties: {
    displayName: office365_ConnectionName
    #disable-next-line BCP037
    parameterValueType: 'Alternative'
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'office365')
    }
  }
}

'@
        ConvertTo-BicepFile -Json $script:template | Should -BeExactly $expected.Replace("`r`n", "`n")
    }

    It 'names variables in camel case, or as the caller says, and the connection after its variable' {
        $pascal = ConvertTo-BicepFile -Json $script:template.Replace('office365-ConnectionName', 'Office365ConnectionName')
        $pascal | Should -Match "(?m)^var office365ConnectionName = "
        $pascal | Should -Match "(?m)^resource office365Connection 'Microsoft\.Web/connections@2016-06-01' = \{$"
        $chosen = ConvertTo-BicepFile -Json $script:template -VariableName @{ 'office365-ConnectionName' = 'mailConnectionName' }
        $chosen | Should -Match "(?m)^var mailConnectionName = "
        $chosen | Should -Match "(?m)^  name: mailConnectionName$"
        $chosen | Should -Match "(?m)^            connectionId: mailConnection\.id$"
    }

    It 'describes a parameter that has no description of its own' {
        $text = ConvertTo-BicepFile -Json $script:template -ParameterDescription @{ PlaybookName = 'The name.'; Secret = 'Not used' }
        $text | Should -Match "(?m)^@description\('The name\.'\)\nparam PlaybookName string = 'Module-T'$"
        $text | Should -Match "(?m)^@secure\(\)\n@description\('A key'\)\nparam Secret string$"
        $text | Should -Not -Match 'Not used'
    }

    It 'leaves a template that has its own location parameter as it is' {
        $own = $script:template.Replace('"PlaybookName": {', '"location": { "type": "string", "defaultValue": "[resourceGroup().location]" }, "PlaybookName": {')
        $text = ConvertTo-BicepFile -Json $own
        @([regex]::Matches($text, '(?m)^param location ')).Count | Should -Be 1
        $text | Should -Match "(?m)^param location string = resourceGroup\(\)\.location$"
        $text | Should -Match "(?m)^  location: resourceGroup\(\)\.location$"
    }

    It 'adds no location parameter when nothing reads the location' {
        $json = ($script:template -replace '"location": "\[resourceGroup\(\)\.location\]",\s*', '').Replace("resourceGroup().location, '/managedApis/office365'", "'westus', '/managedApis/office365'")
        $text = ConvertTo-BicepFile -Json $json
        $text | Should -Not -Match 'param location'
        $text | Should -Match "subscriptionResourceId\('Microsoft\.Web/locations/managedApis', 'westus', 'office365'\)"
    }

    It 'keeps a dependsOn the body does not imply' {
        $json = $script:template.Replace("""connectionId"": ""[resourceId('Microsoft.Web/connections', variables('office365-ConnectionName'))]""", """connectionId"": ""none""")
        ConvertTo-BicepFile -Json $json | Should -Match "(?m)^  dependsOn: \[\n    office365_Connection\n  \]$"
    }

    It 'refuses <Case>' -ForEach @(
        @{ Case = 'outputs'; Change = { param($t) $t.Replace('"resources": [', '"outputs": { "o": { "type": "string", "value": "x" } }, "resources": [') }; Message = "*'outputs'*" }
        @{ Case = 'a copy loop'; Change = { param($t) $t.Replace('"kind": "V1",', '"kind": "V1", "copy": { "name": "c", "count": 2 },') }; Message = "*'copy'*" }
        @{ Case = 'a condition'; Change = { param($t) $t.Replace('"kind": "V1",', '"kind": "V1", "condition": true,') }; Message = "*'condition'*" }
        @{ Case = 'a nested deployment'; Change = { param($t) $t.Replace('"type": "Microsoft.Web/connections"', '"type": "Microsoft.Resources/deployments"') }; Message = '*Nested deployments*' }
        @{ Case = 'a parameter name that is not an identifier'; Change = { param($t) $t.Replace('"Secret":', '"Secret-Key":') }; Message = "*'Secret-Key' is not a Bicep identifier*" }
        @{ Case = 'another deployment scope'; Change = { param($t) $t.Replace('deploymentTemplate.json', 'subscriptionDeploymentTemplate.json') }; Message = '*another deployment scope*' }
        @{ Case = 'a dependsOn outside the template'; Change = { param($t) $t.Replace('"dependsOn": [ "[resourceId(''Microsoft.Web/connections'', variables(''office365-ConnectionName''))]" ]', '"dependsOn": [ "elsewhere" ]') }; Message = "*depends on 'elsewhere'*" }
    ) {
        { ConvertTo-BicepFile -Json (& $Change $script:template) } | Should -Throw $Message
    }
}

Describe 'Compare-iSOCArmTemplate' {
    BeforeAll {
        $script:base = '{"parameters":{"N":{"type":"String","defaultValue":"n"}},"variables":{"v":"[concat(''a-'', parameters(''N''))]"},"resources":[{"type":"T.P/x","apiVersion":"1","name":"[variables(''v'')]","properties":{"b":1,"a":"[concat(''/'', resourceGroup().location)]","provisioningState":"Succeeded"},"dependsOn":["[resourceId(''T.P/y'', ''one'')]","[resourceId(''T.P/y'', ''two'')]"]}],"metadata":{"t":"x"}}'
    }

    It 'treats <Case> as the same deployment' -ForEach @(
        @{ Case = 'format() for concat(), another key order and dependsOn order'; Other = '{"metadata":{"_generator":{"name":"bicep"},"t":"x"},"parameters":{"N":{"defaultValue":"n","type":"string"}},"variables":{"renamed":"[format(''a-{0}'', parameters(''N''))]"},"resources":[{"name":"[variables(''renamed'')]","apiVersion":"1","type":"T.P/x","dependsOn":["[resourceId(''T.P/y'', ''two'')]","[resourceId(''T.P/y'', ''one'')]"],"properties":{"a":"[format(''/{0}'', resourceGroup().location)]","b":1}}]}' }
        @{ Case = 'a Logic App without provisioningState'; Other = $null }
        @{ Case = 'a parameter description'; Other = '{"parameters":{"N":{"type":"String","defaultValue":"n","metadata":{"description":"The name."}}},"variables":{"v":"[concat(''a-'', parameters(''N''))]"},"resources":[{"type":"T.P/x","apiVersion":"1","name":"[variables(''v'')]","properties":{"b":1,"a":"[concat(''/'', resourceGroup().location)]"},"dependsOn":["[resourceId(''T.P/y'', ''one'')]","[resourceId(''T.P/y'', ''two'')]"]}],"metadata":{"t":"x"}}' }
    ) {
        if (-not $Other) { $Other = $script:base.Replace('"type":"T.P/x"', '"type":"Microsoft.Logic/workflows"') ; $first = $script:base.Replace('"type":"T.P/x"', '"type":"Microsoft.Logic/workflows"').Replace(',"provisioningState":"Succeeded"', '') }
        else { $first = $script:base.Replace(',"provisioningState":"Succeeded"', '') }
        Compare-Json -Expected $first -Actual $Other | Should -BeNullOrEmpty
    }

    It 'reads an inlined location parameter as resourceGroup().location' {
        $first = $script:base.Replace(',"provisioningState":"Succeeded"', '')
        $located = $first.Replace('"parameters":{', '"parameters":{"location":{"type":"string","defaultValue":"[resourceGroup().location]"},').Replace('resourceGroup().location', 'parameters(''location'')').Replace('"defaultValue":"[parameters(''location'')]"', '"defaultValue":"[resourceGroup().location]"')
        Compare-Json -Expected $first -Actual $located | Should -BeExactly 'parameters.location: missing in the first, {"defaultValue":"{rg.location}","type":"string"} in the second'
        Compare-Json -Expected $first -Actual $located -InlineParameter location | Should -BeNullOrEmpty
        Compare-Json -Expected $first -Actual $located.Replace('"defaultValue":"[resourceGroup().location]"', '"defaultValue":"westus"') -InlineParameter location |
            Should -BeExactly 'resources[0].properties.a: "/{rg.location}" in the first, "/westus" in the second'
    }

    It 'names the first difference: <Case>' -ForEach @(
        @{ Case = 'a value'; Change = { param($t) $t.Replace('"b":1', '"b":2') }; Expected = 'resources[0].properties.b: 1 in the first, 2 in the second' }
        @{ Case = 'a parameter default'; Change = { param($t) $t.Replace('"defaultValue":"n"', '"defaultValue":"m"') }; Expected = 'parameters.N.defaultValue: "n" in the first, "m" in the second' }
        @{ Case = 'an expression'; Change = { param($t) $t.Replace('resourceGroup().location', 'resourceGroup().name') }; Expected = 'resources[0].properties.a: "/{rg.location}" in the first, "/{rg.name}" in the second' }
        @{ Case = 'a dependency'; Change = { param($t) $t.Replace(',"[resourceId(''T.P/y'', ''two'')]"', '') }; Expected = 'resources[0].dependsOn: 2 items in the first, 1 in the second' }
        @{ Case = 'a type'; Change = { param($t) $t.Replace('"b":1', '"b":"1"') }; Expected = 'resources[0].properties.b: 1 in the first, "1" in the second' }
    ) {
        Compare-Json -Expected $script:base -Actual (& $Change $script:base) | Should -BeExactly $Expected
    }
}

Describe 'Invoke-iSOCBicep and round trips through the Bicep CLI' {
    BeforeAll {
        $script:bicep = Get-Command bicep -CommandType Application -ErrorAction SilentlyContinue
    }

    It 'has the Bicep CLI on the PATH, as Bicep playbooks need' {
        $script:bicep | Should -Not -BeNullOrEmpty -Because 'install it with az bicep install and put ~/.azure/bin on the PATH, or see https://aka.ms/bicep/install'
    }

    It 'builds several files in one run, reports errors per file and leaves nothing beside the sources' {
        $folder = Join-Path $TestDrive 'build'
        New-Item -ItemType Directory -Path (Join-Path $folder 'sub') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $folder 'good.bicep') -Value "param name string = 'x'`noutput n string = name"
        Set-Content -LiteralPath (Join-Path $folder 'sub/bad.bicep') -Value 'resource x = {'
        $builds = @(Invoke-InModule { param($F) Invoke-iSOCBicep -Path @((Join-Path $F 'sub/bad.bicep'), (Join-Path $F 'good.bicep')) } @{ F = $folder })
        $builds.Count | Should -Be 2
        $builds[0].Succeeded | Should -BeFalse
        @($builds[0].Errors).Count | Should -BeGreaterThan 0
        $builds[1].Succeeded | Should -BeTrue
        $builds[1].Template['parameters']['name']['defaultValue'] | Should -BeExactly 'x'
        @(Get-ChildItem -LiteralPath $folder -Recurse -Filter '*.json').Count | Should -Be 0
    }

    It 'writes the fixture playbooks as Bicep that deploys what their JSON deploys' {
        $paths = @(Get-ChildItem -LiteralPath $script:fixturePlaybooks -Recurse -Filter '*.json' | Where-Object { $_.Name -notlike '*.parameters.json' -and $_.Directory.Name -ne 'Template' -and $_.Name -ne 'NotArm.json' } | ForEach-Object { $_.FullName })
        $paths.Count | Should -BeGreaterOrEqual 2
        @(Test-RoundTrip -JsonPath $paths) | Should -BeNullOrEmpty
    }

    It 'round-trips every awkward value' {
        $path = Join-Path $TestDrive 'Awkward.json'
        $template = [ordered]@{
            '$schema'      = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#'
            contentVersion = '1.0.0.0'
            parameters     = [ordered]@{ PlaybookName = [ordered]@{ type = 'string'; defaultValue = 'Awkward' }; Flag = [ordered]@{ type = 'bool'; defaultValue = $true } }
            variables      = [ordered]@{}
            resources      = @([ordered]@{
                    type       = 'Microsoft.Logic/workflows'
                    apiVersion = '2019-05-01'
                    name       = "[parameters('PlaybookName')]"
                    location   = '[resourceGroup().location]'
                    properties = [ordered]@{
                        definition = [ordered]@{
                            'Action with spaces (V3)' = [ordered]@{ query = "Table`n| where A == 'b'`n| project `${not}, `$c`n"; crlf = "a`r`nb"; endsInQuote = "x`n'y'" }
                            numbers                   = [ordered]@{ int = 3; negative = -2; real = 1.5; zero = 0 }
                            mixed                     = @($null, $true, $false, @(), [ordered]@{}, 'one', @('nested'))
                            escaped                   = '[[not an expression]'
                            quoted                    = "it's a \ backslash and `${x}"
                            unicode                   = "caf$([char]0xe9) $([char]0x2192) $([char]1)"
                            built                     = "[concat('Hello ', parameters('PlaybookName'), '!')]"
                        }
                    }
                })
        }
        Set-Content -LiteralPath $path -Value (ConvertTo-Json -InputObject $template -Depth 20)
        @(Test-RoundTrip -JsonPath $path) | Should -BeNullOrEmpty
    }
}

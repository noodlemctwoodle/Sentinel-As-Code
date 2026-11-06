#Requires -Version 7.2

<#
.SYNOPSIS
    Check a content type definition is complete and names things that exist.

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/Test-iSOCContentTypeDefinition.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-23
    Version:      0.2.1
    Last Updated: 2026-11-06
    Requires:     PowerShell 7.2+

    Docs/Modules/iSOCDeployments/Architecture.md lists the keys, the values
    each may take and the handlers each capability needs; keep the two in
    step.
#>

# Keeps the file help above from being read as the help of the function below.

function Test-iSOCContentTypeDefinition {
    <#
    .SYNOPSIS
        List what is wrong with a definition.

    .DESCRIPTION
        Checks every key is present with a value it may take, that the API
        version and prerequisites name entries in their tables, that every
        handler names a function the module has, that every capability has
        the handlers it needs, and that every field names a comparer
        Compare-iSOCFieldValue knows. A field may also name the Kind of item
        it applies to (a Scheduled rule's schedule, say), and has no other
        keys.

        Capability   Handlers it needs
        Deploy       ReadRepo, Validate, ToRequest
        Export       ReadRepo, ReadWorkspace, Classify, ToRepoFile, GetRepoPath
        Compare      ReadRepo, ReadWorkspace, Classify, ToRequest, ToComparable
        Sync         Compare's, and UpdateRepoFile, ToRepoFile, GetRepoPath
        Dependencies ReadRepo, GetQuery

    .PARAMETER Definition
        The definition, as a Get-iSOC<Type>Definition function returns it.

    .OUTPUTS
        [string] One line per problem; nothing when the definition is sound.

    .EXAMPLE
        Test-iSOCContentTypeDefinition -Definition (Get-iSOCAnalyticsRuleDefinition)
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Definition
    )

    $issues = [System.Collections.Generic.List[string]]::new()
    $choices = @{
        Layout            = 'File', 'Folder'
        Format            = 'Yaml', 'Json', 'Bicep'
        Endpoint          = 'Arm', 'Graph'
        Scope             = 'Workspace', 'ResourceGroup', 'PlaybookResourceGroup', 'Tenant'
        MissingDependency = 'DeployDisabled', 'Skip', 'Deploy'
    }
    $handlerNames = 'ReadRepo', 'ReadWorkspace', 'Classify', 'Validate', 'ToRequest', 'Deploy', 'Order',
    'ToComparable', 'GetTemplates', 'ToRepoFile', 'UpdateRepoFile', 'GetRepoPath', 'GetQuery'
    $needs = @{
        Deploy       = 'ReadRepo', 'Validate', 'ToRequest'
        Export       = 'ReadRepo', 'ReadWorkspace', 'Classify', 'ToRepoFile', 'GetRepoPath'
        Compare      = 'ReadRepo', 'ReadWorkspace', 'Classify', 'ToRequest', 'ToComparable'
        Sync         = 'ReadRepo', 'ReadWorkspace', 'Classify', 'ToRequest', 'ToComparable', 'UpdateRepoFile', 'ToRepoFile', 'GetRepoPath'
        Dependencies = 'ReadRepo', 'GetQuery'
    }

    foreach ($key in 'Name', 'DisplayName', 'RepoFolder', 'Layout', 'Format', 'FilePattern', 'Recurse', 'Endpoint', 'Scope',
        'CollectionPath', 'ApiVersion', 'IdentityKey', 'DeployOrder', 'SettleSeconds', 'MissingDependency', 'Capabilities', 'Prerequisites',
        'Handlers', 'Fields') {
        if (-not $Definition.ContainsKey($key)) { $issues.Add("missing $key") }
    }
    if ($issues.Count -gt 0) { return $issues.ToArray() }

    foreach ($key in 'Name', 'DisplayName', 'IdentityKey') {
        if ([string]::IsNullOrWhiteSpace([string]$Definition[$key])) { $issues.Add("$key is empty") }
    }
    if ($Definition.Name -notmatch '^[A-Z][A-Za-z]+$') { $issues.Add("Name '$($Definition.Name)' is not one PascalCase word") }
    if ([string]$Definition.RepoFolder -notmatch '^Content/[^\\]+$') { $issues.Add("RepoFolder '$($Definition.RepoFolder)' is not a forward-slash path under Content/") }
    if ([string]$Definition.CollectionPath -notmatch '^/') { $issues.Add("CollectionPath '$($Definition.CollectionPath)' does not start with '/'") }
    foreach ($key in $choices.Keys) {
        if ($Definition[$key] -notin $choices[$key]) { $issues.Add("$key '$($Definition[$key])' is not one of $($choices[$key] -join ', ')") }
    }
    if (@($Definition.FilePattern | Where-Object { $_ }).Count -eq 0) { $issues.Add('FilePattern is empty') }
    if ($Definition.Recurse -isnot [bool]) { $issues.Add('Recurse is not $true or $false') }
    if ($Definition.DeployOrder -isnot [int]) { $issues.Add('DeployOrder is not a whole number') }
    if ($Definition.SettleSeconds -isnot [int] -or $Definition.SettleSeconds -lt 0) { $issues.Add('SettleSeconds is not a whole number of seconds') }

    $apis = Get-iSOCApiVersion
    if (-not $apis.Contains([string]$Definition.ApiVersion)) { $issues.Add("ApiVersion '$($Definition.ApiVersion)' is not in the API table") }

    $requirements = @(Get-iSOCRequirement | ForEach-Object { $_.Name })
    foreach ($p in @($Definition.Prerequisites)) {
        if ($p -notin $requirements) { $issues.Add("prerequisite '$p' is not in the requirement table") }
    }

    $handlers = $Definition.Handlers
    if ($handlers -isnot [hashtable]) {
        $issues.Add('Handlers is not a hashtable')
        $handlers = @{}
    }
    foreach ($h in $handlers.Keys) {
        if ($h -notin $handlerNames) { $issues.Add("unknown handler '$h'"); continue }
        $command = [string]$handlers[$h]
        if (-not $ExecutionContext.SessionState.InvokeCommand.GetCommand($command, 'Function')) {
            $issues.Add("handler $h names '$command', which the module does not define")
        }
    }
    foreach ($capability in @($Definition.Capabilities)) {
        if (-not $needs.ContainsKey([string]$capability)) { $issues.Add("unknown capability '$capability'"); continue }
        foreach ($h in $needs[$capability]) {
            if (-not $handlers.ContainsKey($h)) { $issues.Add("capability $capability needs a $h handler") }
        }
    }

    $comparers = (Get-Command Compare-iSOCFieldValue).Parameters['Comparer'].Attributes |
        Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] } |
        ForEach-Object { $_.ValidValues }
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($field in @($Definition.Fields)) {
        if ($field -isnot [hashtable] -or [string]::IsNullOrWhiteSpace([string]$field.Name)) { $issues.Add('a field has no Name'); continue }
        if ($field.Comparer -notin $comparers) { $issues.Add("field $($field.Name) uses unknown comparer '$($field.Comparer)'") }
        if (-not $seen.Add([string]$field.Name)) { $issues.Add("field $($field.Name) is listed twice") }
        if ($field.ContainsKey('Kind') -and ($field.Kind -isnot [string] -or [string]::IsNullOrWhiteSpace($field.Kind))) { $issues.Add("field $($field.Name) has a Kind that is not a name") }
        foreach ($k in @($field.Keys | Where-Object { $_ -notin 'Name', 'Comparer', 'Kind' })) { $issues.Add("field $($field.Name) has unknown key '$k'") }
    }

    $issues.ToArray()
}

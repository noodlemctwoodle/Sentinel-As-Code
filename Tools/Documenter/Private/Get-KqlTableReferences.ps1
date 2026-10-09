#Requires -Version 7.2

<#
.SYNOPSIS
    Work out which Log Analytics tables each analytics rule and each rule
    template reads, from their KQL and connector metadata.

.DESCRIPTION
    The Documenter needs a table-to-rule map for three things: finding
    high-volume tables that no enabled rule looks at, spotting tables that
    enabled rules depend on but that have gone silent, and suggesting rule
    templates for data that is ingested but not detected on. All three need
    the same answer to the same question: which tables does this KQL read?

    The identifier extraction is Sentinel.Common's Get-KqlBareIdentifiers,
    the same code that builds dependencies.json for the repository's own
    content. It understands let-bindings, union, join, lookup and function
    calls, which a start-of-line regex does not. On top of it this file:

      - drops ASIM parser and function names (they are functions, not tables);
      - adds the tables a template declares through
        requiredDataConnectors[].dataTypes, whose entries look like
        'OfficeActivity (SharePoint)';
      - flags templates that are deprecated or already deployed, so the
        suggestions never recommend retired content or content already in use.

    The collector runs these functions and writes the results to
    _raw/rule-table-references.json and _raw/template-table-references.json,
    so the gap engine, the renderer and the SharePoint build read a plain
    file and never need Sentinel.Common or Az.Accounts themselves.

    Callers must import Modules/Sentinel.Common before dot-sourcing this file.

.NOTES
    File:         Tools/Documenter/Private/Get-KqlTableReferences.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-09
    Version:      0.1.0
    Last Updated: 2026-10-09
    Requires:     PowerShell 7.2+, Sentinel.Common (imported by the caller)

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block. The table-to-rule mapping and
    the template-suggestion idea come from the Sentinel health-check script
    contributed to this project.
#>

# ASIM parsers and the im/ASim function families are functions, not tables.
$script:KqlFunctionNamePattern = '^(_?ASim|_Im_|im)\w+$'

function Get-KqlPropertyValue {
    <#
    .SYNOPSIS
        Read a property that may be absent, without tripping StrictMode.

    .PARAMETER Object
        A PSObject or hashtable.

    .PARAMETER Name
        Property name.

    .PARAMETER Default
        Returned when the property is missing or null.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)] [AllowNull()] $Object,
        [Parameter(Mandatory = $true)] [string] $Name,
        [Parameter(Mandatory = $false)] $Default = $null
    )

    if ($null -eq $Object) { return $Default }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name) -and $null -ne $Object[$Name]) { return $Object[$Name] }
        return $Default
    }
    if ($Object.PSObject.Properties.Name -contains $Name -and $null -ne $Object.$Name) { return $Object.$Name }
    return $Default
}

function Resolve-KqlTableNames {
    <#
    .SYNOPSIS
        Return the sorted, unique table names a query reads, plus any tables
        declared through connector data types.

    .PARAMETER Query
        KQL text. May be empty.

    .PARAMETER DataTypes
        Values of requiredDataConnectors[].dataTypes, for example
        'OfficeActivity (SharePoint)'. The first identifier token of each
        entry is taken as the table name.

    .OUTPUTS
        [string[]]
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $false)] [AllowNull()] [AllowEmptyString()] [string] $Query,
        [Parameter(Mandatory = $false)] [AllowNull()] [string[]] $DataTypes
    )

    $names = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)

    if (-not [string]::IsNullOrWhiteSpace($Query)) {
        $candidates = [System.Collections.Generic.List[string]]::new()
        foreach ($id in @(Get-KqlBareIdentifiers -Query $Query)) { $candidates.Add([string]$id) }

        # Get-KqlBareIdentifiers takes only the first operand after 'union';
        # templates often write 'union SecurityEvent, WindowsEvent', so pick up
        # the rest of a comma-separated list here.
        $stripped = Remove-KqlComments -Query $Query
        foreach ($m in [regex]::Matches($stripped, '(?im)\bunion\b(?:\s+(?:kind|withsource|isfuzzy|hint\.[a-z]+)\s*=\s*[A-Za-z0-9_]+)*\s+([A-Za-z_][A-Za-z0-9_]*(?:\s*,\s*[A-Za-z_][A-Za-z0-9_]*)+)')) {
            foreach ($part in ($m.Groups[1].Value -split ',')) { $candidates.Add($part.Trim()) }
        }

        foreach ($id in $candidates) {
            if ([string]::IsNullOrWhiteSpace($id)) { continue }
            if ($id -match $script:KqlFunctionNamePattern) { continue }
            [void]$names.Add($id)
        }
    }

    foreach ($dt in @($DataTypes)) {
        if ([string]::IsNullOrWhiteSpace($dt)) { continue }
        if ("$dt" -match '^\s*([A-Za-z_][A-Za-z0-9_]*)') { [void]$names.Add($Matches[1]) }
    }

    # Emitted item by item so callers get a plain string array whether they
    # assign the result, wrap it in @() or pipe it.
    return @($names | Sort-Object)
}

function Get-RuleTableReferences {
    <#
    .SYNOPSIS
        Map every analytics rule to the tables its query reads.

    .PARAMETER AlertRules
        Alert rule objects as the Sentinel REST API returns them
        (name, kind, properties.displayName, properties.enabled,
        properties.query).

    .OUTPUTS
        [pscustomobject[]] RuleId, RuleName, Kind, Enabled, Tables.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param([Parameter(Mandatory = $false)] [AllowNull()] [object[]] $AlertRules)

    $rows = foreach ($rule in @($AlertRules)) {
        if ($null -eq $rule) { continue }
        $props = Get-KqlPropertyValue $rule 'properties'
        [pscustomobject]@{
            RuleId   = [string](Get-KqlPropertyValue $rule 'name' '')
            RuleName = [string](Get-KqlPropertyValue $props 'displayName' '')
            Kind     = [string](Get-KqlPropertyValue $rule 'kind' '')
            Enabled  = [bool](Get-KqlPropertyValue $props 'enabled' $false)
            Tables   = @(Resolve-KqlTableNames -Query ([string](Get-KqlPropertyValue $props 'query' '')))
        }
    }
    return @($rows)
}

function Get-TemplateTableReferences {
    <#
    .SYNOPSIS
        Map every rule template to the tables it needs, and flag templates
        that are deprecated or already deployed.

    .PARAMETER Templates
        Alert rule template objects as the REST API returns them.

    .PARAMETER AlertRules
        The workspace's alert rules, used to detect templates that are
        already deployed through alertRuleTemplateName.

    .OUTPUTS
        [pscustomobject[]] TemplateId, DisplayName, Kind, Severity, Tactics,
        AlreadyDeployed, Deprecated, Tables.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory = $false)] [AllowNull()] [object[]] $Templates,
        [Parameter(Mandatory = $false)] [AllowNull()] [object[]] $AlertRules
    )

    $deployedTemplateNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($rule in @($AlertRules)) {
        if ($null -eq $rule) { continue }
        $tplName = Get-KqlPropertyValue (Get-KqlPropertyValue $rule 'properties') 'alertRuleTemplateName'
        if (-not [string]::IsNullOrWhiteSpace($tplName)) { [void]$deployedTemplateNames.Add([string]$tplName) }
    }

    $rows = foreach ($tpl in @($Templates)) {
        if ($null -eq $tpl) { continue }
        $props = Get-KqlPropertyValue $tpl 'properties'
        $templateId = [string](Get-KqlPropertyValue $tpl 'name' '')
        $displayName = [string](Get-KqlPropertyValue $props 'displayName' '')
        $createdCount = 0
        $rawCount = Get-KqlPropertyValue $props 'alertRulesCreatedByTemplateCount' 0
        [void][int]::TryParse([string]$rawCount, [ref]$createdCount)

        $dataTypes = [System.Collections.Generic.List[string]]::new()
        foreach ($rdc in @(Get-KqlPropertyValue $props 'requiredDataConnectors' @())) {
            foreach ($dt in @(Get-KqlPropertyValue $rdc 'dataTypes' @())) {
                if (-not [string]::IsNullOrWhiteSpace($dt)) { $dataTypes.Add([string]$dt) }
            }
        }

        [pscustomobject]@{
            TemplateId      = $templateId
            DisplayName     = $displayName
            Kind            = [string](Get-KqlPropertyValue $tpl 'kind' '')
            Severity        = [string](Get-KqlPropertyValue $props 'severity' '')
            Tactics         = @(Get-KqlPropertyValue $props 'tactics' @() | ForEach-Object { [string]$_ })
            AlreadyDeployed = ($deployedTemplateNames.Contains($templateId) -or $createdCount -gt 0)
            Deprecated      = ($displayName -match '(?i)\bdeprecated\b')
            Tables          = @(Resolve-KqlTableNames -Query ([string](Get-KqlPropertyValue $props 'query' '')) -DataTypes $dataTypes.ToArray())
        }
    }
    return @($rows)
}

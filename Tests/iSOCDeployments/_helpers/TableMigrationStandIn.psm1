#Requires -Version 7.2

<#
.SYNOPSIS
    A stand-in workspace for the classic table migration review, served the
    way ARM serves it.

.DESCRIPTION
    Get-TableMigrationStandIn builds one workspace whose content exercises
    the review: classic and DCR-based tables, AzureDiagnostics, parsers that
    chain and cycle, aliases that clash with a table or a column or are too
    short, analytics rules that name a parser in a comment, a string, a
    quoted identifier, another workspace or a let binding, workbooks whose
    content the list returns only with canFetchContent (and one only on its
    own GET), data collection rules, Logic Apps that name a parser in a
    query or only as a key, and Content Hub packages for the tables the
    shipped solution mapping knows.

    Get-TableMigrationStandInAnswer answers one GET against it: the tables,
    alert rules, saved searches, workbooks (list or one), data collection
    rules, Logic Apps or Content Hub packages, as { value = [...] } or the
    one item. The script's stand-in Invoke-RestMethod and the module's
    mocked Invoke-iSOCRestRequest both call it, so the two read the same
    workspace.

    ConvertTo-TableMigrationContent builds, from the same workspace, the
    content object the review's Get-WorkspaceContent and
    Read-iSOCTableMigrationContent return, with every workbook's content,
    for comparing the analysis functions directly.

.NOTES
    File:         Tests/iSOCDeployments/_helpers/TableMigrationStandIn.psm1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-04
    Version:      0.1.0
    Last Updated: 2026-11-04
    Requires:     PowerShell 7.2+
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-TableMigrationStandIn {
    param(
        [string] $SubscriptionId = '11111111-2222-3333-4444-555555555555'
    )

    $ws = "/subscriptions/$SubscriptionId/resourceGroups/rg-sentinel/providers/Microsoft.OperationalInsights/workspaces/law-sentinel"
    $table = {
        param($Name, $Type, $SubType, [string[]] $Columns, [switch] $NoColumns)
        $schema = [ordered]@{ name = $Name; tableType = $Type; tableSubType = $SubType }
        if (-not $NoColumns) { $schema.columns = @($Columns | ForEach-Object { [ordered]@{ name = $_; type = 'string' } }) }
        [ordered]@{ id = "$ws/tables/$Name"; name = $Name; properties = [ordered]@{ plan = 'Analytics'; retentionInDays = 90; totalRetentionInDays = 180; schema = $schema } }
    }
    $search = {
        param($Name, $DisplayName, $Category, $Query, $Alias)
        $p = [ordered]@{ displayName = $DisplayName; category = $Category; query = $Query }
        if ($Alias) { $p.functionAlias = $Alias }
        [ordered]@{ id = "$ws/savedSearches/$Name"; name = $Name; properties = $p }
    }
    $rule = {
        param($Name, $DisplayName, $Query, $Severity = 'Medium', $Enabled = $true)
        $p = [ordered]@{ enabled = $Enabled; severity = $Severity }
        if ($null -ne $DisplayName) { $p.displayName = $DisplayName }
        if ($null -ne $Query) { $p.query = $Query }
        [ordered]@{ id = "$ws/providers/Microsoft.SecurityInsights/alertRules/$Name"; name = $Name; kind = 'Scheduled'; properties = $p }
    }
    $workbook = {
        param($Name, $DisplayName, $Data, [switch] $OnlyOnItsOwn)
        [ordered]@{ id = "/subscriptions/$SubscriptionId/resourceGroups/rg-sentinel/providers/Microsoft.Insights/workbooks/$Name"; name = $Name; onlyOnItsOwn = [bool]$OnlyOnItsOwn; properties = [ordered]@{ displayName = $DisplayName; category = 'sentinel'; serializedData = $Data } }
    }
    $queries = { param([string[]] $Query) ConvertTo-Json -Depth 10 -Compress -InputObject ([ordered]@{ version = 'Notebook/1.0'; items = @($Query | ForEach-Object { [ordered]@{ type = 3; content = [ordered]@{ query = $_; size = 0 } } }) + @([ordered]@{ type = 12; content = [ordered]@{ items = @([ordered]@{ type = 3; content = [ordered]@{ query = 'OfficeWrapper | take 3' } }) } }) }) }

    [ordered]@{
        subscriptionId          = $SubscriptionId
        tables                  = @(
            & $table 'OfficeActivity_CL' 'CustomLog' 'Classic' 'TimeGenerated', 'Location', 'Message', 'Computer'
            & $table 'MyApp_CL' 'CustomLog' 'Classic' 'TimeGenerated', 'RawData', 'Status_s'
            & $table 'MyApp_CL_v2' 'CustomLog' 'Classic' 'TimeGenerated'
            & $table 'Okta_CL' 'CustomLog' 'Classic' 'TimeGenerated', 'Actor_s'
            & $table 'Tenable_IE_CL' 'CustomLog' 'Classic' 'TimeGenerated'
            & $table 'Lonely_CL' 'CustomLog' 'Classic' -NoColumns
            & $table 'AzureDiagnostics' 'CustomLog' 'Classic' 'TimeGenerated', 'Category'
            & $table 'NewApp_CL' 'CustomLog' 'DataCollectionRuleBased' 'TimeGenerated'
            & $table 'SecurityEvent' 'Microsoft' 'Any' 'TimeGenerated', 'EventID', 'Account'
            & $table 'Update' 'Microsoft' 'Any' 'TimeGenerated', 'UpdateID'
        )
        savedSearches           = @(
            & $search 'p-office' 'Office Activity Parser' 'Parsers' 'OfficeActivity_CL | extend Location = tostring(Location)' 'OfficeActivityParser'
            & $search 'p-wrapper' 'Office Wrapper' 'Parsers' 'OfficeActivityParser | where Message has "x"' 'OfficeWrapper'
            & $search 'p-deep' 'Deep One' 'Parsers' 'OfficeWrapper | take 5' 'DeepOne'
            & $search 'p-deeper' 'Deeper Two' 'Parsers' 'DeepOne | take 5' 'DeeperTwo'
            & $search 'p-update' 'Update Parser' 'Parsers' 'MyApp_CL | project TimeGenerated' 'Update'
            & $search 'p-location' 'Location Parser' 'Parsers' 'MyApp_CL_v2 | take 1' 'Location'
            & $search 'p-short' 'Short Parser' 'Parsers' 'OfficeWrapper | take 1' 'abc'
            & $search 'p-cycle-a' 'Cycle A' 'Parsers' 'CycleB | union OfficeActivityParser' 'CycleA'
            & $search 'p-cycle-b' 'Cycle B' 'Parsers' 'CycleA | take 1' 'CycleB'
            & $search 'p-okta' 'Okta Parser' 'Parsers' 'Okta_CL | extend User = Actor_s' 'OktaParser'
            & $search 'hq-wrapper' 'Hunt wrapper' 'Hunting Queries' 'OfficeWrapper | summarize count()'
            & $search 'hq-case' 'Hunt case' 'Hunting Queries' 'officeactivityparser | take 1'
            & $search 'hq-deeper' 'Hunt deeper' 'Hunting Queries' 'DeeperTwo | take 1'
            & $search 'ss-myapp' 'MyApp search' 'General' 'MyApp_CL | where Status_s == "fail"'
            & $search 'ss-shadow' 'Shadowed' 'Log Management' 'let OfficeActivityParser = datatable(x:int)[1]; OfficeActivityParser'
            & $search 'ss-abc' 'Uses abc' 'General' 'abc | take 1'
            & $search 'ss-update' 'Update search' 'General' 'Update | where UpdateID != ""'
        )
        alertRules              = @(
            & $rule 'r-indirect' 'Rule via parser' 'OfficeActivityParser | where Location == "UK"' 'High' $true
            & $rule 'r-depth2' 'Rule via wrapper' 'OfficeWrapper | take 1' 'Medium' $false
            & $rule 'r-myapp' 'Rule on MyApp' 'MyApp_CL | where Status_s == "x"'
            & $rule 'r-v2' 'Rule on v2' 'MyApp_CL_v2 | take 1'
            & $rule 'r-comment' 'Rule with comment' "// OfficeActivityParser was here`nSecurityEvent | take 1"
            & $rule 'r-string' 'Rule with string' "SecurityEvent | where Account == 'OfficeWrapper'"
            & $rule 'r-update' 'Rule on Update' 'Update | take 1'
            & $rule 'r-both' 'Rule both' 'OfficeActivity_CL | union OfficeActivityParser'
            & $rule 'r-quoted' 'Rule quoted' "['OfficeWrapper'] | take 1"
            & $rule 'r-xcluster' 'Rule cross workspace' 'workspace("other").OfficeActivityParser | take 1'
            & $rule 'r-okta' 'Okta rule' 'OktaParser | where User == "x"'
            & $rule 'r-noname' $null 'MyApp_CL | take 1'
            & $rule 'r-fusion' 'Fusion' $null 'High' $true
        )
        workbooks               = @(
            & $workbook 'wb-office' 'Office workbook' (& $queries 'OfficeWrapper | count', 'MyApp_CL | take 1', 'Okta_CL | take 1')
            & $workbook 'wb-inherited' 'Inherited workbook' (& $queries 'MyApp_CL | summarize count()') -OnlyOnItsOwn
            & $workbook 'wb-broken' 'Broken workbook' 'not json'
        )
        dataCollectionRules     = @(
            [ordered]@{ id = "/subscriptions/$SubscriptionId/resourceGroups/rg-dcr/providers/Microsoft.Insights/dataCollectionRules/dcr-myapp"; name = 'dcr-myapp'; properties = [ordered]@{ dataFlows = @([ordered]@{ transformKql = "source | where Category == 'MyApp_CL'" }, [ordered]@{ transformKql = 'source' }) } }
            [ordered]@{ id = "/subscriptions/$SubscriptionId/resourceGroups/rg-dcr/providers/Microsoft.Insights/dataCollectionRules/dcr-alias"; name = 'dcr-alias'; properties = [ordered]@{ dataFlows = @([ordered]@{ transformKql = 'OfficeActivityParser' }) } }
            [ordered]@{ id = "/subscriptions/$SubscriptionId/resourceGroups/rg-dcr/providers/Microsoft.Insights/dataCollectionRules/dcr-empty"; name = 'dcr-empty'; properties = [ordered]@{} }
        )
        logicApps               = @(
            [ordered]@{ id = "/subscriptions/$SubscriptionId/resourceGroups/rg-auto/providers/Microsoft.Logic/workflows/pb-query"; name = 'pb-query'; properties = [ordered]@{ state = 'Enabled'; definition = [ordered]@{ actions = [ordered]@{ Run_query = [ordered]@{ type = 'ApiConnection'; inputs = [ordered]@{ body = 'OfficeWrapper | where Message has "x"' } } } } } }
            [ordered]@{ id = "/subscriptions/$SubscriptionId/resourceGroups/rg-auto/providers/Microsoft.Logic/workflows/pb-key"; name = 'pb-key'; properties = [ordered]@{ state = 'Enabled'; definition = [ordered]@{ actions = [ordered]@{ OfficeActivityParser = [ordered]@{ type = 'Compose'; inputs = 'hello' } } } } }
            [ordered]@{ id = "/subscriptions/$SubscriptionId/resourceGroups/rg-auto/providers/Microsoft.Logic/workflows/pb-direct"; name = 'pb-direct'; properties = [ordered]@{ state = 'Disabled'; definition = [ordered]@{ actions = [ordered]@{ Run = [ordered]@{ inputs = [ordered]@{ query = 'MyApp_CL | take 1' } } } } } }
            [ordered]@{ id = "/subscriptions/$SubscriptionId/resourceGroups/rg-auto/providers/Microsoft.Logic/workflows/pb-nodef"; name = 'pb-nodef'; properties = [ordered]@{ state = 'Disabled' } }
        )
        contentProductPackages  = @(
            [ordered]@{ id = "$ws/providers/Microsoft.SecurityInsights/contentProductPackages/m365"; name = 'm365'; properties = [ordered]@{ contentKind = 'Solution'; displayName = 'Microsoft 365'; installedVersion = '3.0.0'; dependencies = [ordered]@{ criteria = @([ordered]@{ kind = 'DataConnector'; contentId = 'Office365' }) } } }
            [ordered]@{ id = "$ws/providers/Microsoft.SecurityInsights/contentProductPackages/okta"; name = 'okta'; properties = [ordered]@{ contentKind = 'Solution'; displayName = 'Okta Single Sign-On'; dependencies = [ordered]@{ criteria = @([ordered]@{ kind = 'AnalyticsRule'; contentId = 'x' }, [ordered]@{ kind = 'DataConnector'; contentId = 'OktaSSO_Polling' }) } } }
            [ordered]@{ id = "$ws/providers/Microsoft.SecurityInsights/contentProductPackages/tenable"; name = 'tenable'; properties = [ordered]@{ contentKind = 'Solution'; displayName = 'TenableAD'; installedVersion = '1.0.0'; dependencies = [ordered]@{ criteria = @([ordered]@{ kind = 'DataConnector'; contentId = 'TenableIECCPDefinition' }) } } }
            [ordered]@{ id = "$ws/providers/Microsoft.SecurityInsights/contentProductPackages/standalone"; name = 'standalone'; properties = [ordered]@{ contentKind = 'Standalone'; displayName = 'Something' } }
        )
    }
}

function ConvertTo-StandInItem {
    param($Item, [switch] $WithoutContent)
    $json = ConvertTo-Json -InputObject $Item -Depth 30 -Compress
    $copy = $json | ConvertFrom-Json -Depth 30
    if ($copy.PSObject.Properties['onlyOnItsOwn']) { $copy.PSObject.Properties.Remove('onlyOnItsOwn') }
    if ($WithoutContent -and $copy.properties.PSObject.Properties['serializedData']) { $copy.properties.PSObject.Properties.Remove('serializedData') }
    $copy
}

function Get-TableMigrationStandInAnswer {
    param(
        [Parameter(Mandatory)]
        $StandIn,

        [Parameter(Mandatory)]
        [string] $Path,

        [hashtable] $Query = @{}
    )

    $fetch = $Query['canFetchContent'] -eq 'true'
    $list = { param($Items) @{ value = @($Items | ForEach-Object { ConvertTo-StandInItem -Item $_ }) } }
    switch -Regex ($Path) {
        '/workspaces/[^/]+/tables$' { return & $list $StandIn.tables }
        '/providers/Microsoft\.SecurityInsights/alertRules$' { return & $list $StandIn.alertRules }
        '/workspaces/[^/]+/savedSearches$' { return & $list $StandIn.savedSearches }
        '/providers/Microsoft\.SecurityInsights/contentProductPackages$' { return & $list $StandIn.contentProductPackages }
        '/providers/Microsoft\.Insights/dataCollectionRules$' { return & $list $StandIn.dataCollectionRules }
        '/providers/Microsoft\.Logic/workflows$' { return & $list $StandIn.logicApps }
        '/providers/Microsoft\.Insights/workbooks$' {
            if ($Query['category'] -ne 'sentinel') { throw "unexpected workbook category '$($Query['category'])'" }
            return @{ value = @($StandIn.workbooks | ForEach-Object { ConvertTo-StandInItem -Item $_ -WithoutContent:(-not $fetch -or $_.onlyOnItsOwn) }) }
        }
        '/providers/Microsoft\.Insights/workbooks/([^/]+)$' {
            $name = $Matches[1]
            $wb = @($StandIn.workbooks | Where-Object { $_.name -eq $name })
            if (-not $wb) { throw "no workbook $name" }
            return ConvertTo-StandInItem -Item $wb[0] -WithoutContent:(-not $fetch)
        }
    }
    throw "The stand-in workspace has no answer for $Path"
}

function ConvertTo-TableMigrationContent {
    param(
        [Parameter(Mandatory)]
        $StandIn
    )
    $items = { param($Items) @($Items | ForEach-Object { ConvertTo-StandInItem -Item $_ }) }
    $saved = & $items $StandIn.savedSearches
    [pscustomobject]@{
        AlertRules     = & $items $StandIn.alertRules
        SavedSearches  = $saved
        HuntingQueries = @($saved | Where-Object { $_.properties.category -eq 'Hunting Queries' })
        Parsers        = @($saved | Where-Object { $_.properties.PSObject.Properties['functionAlias'] -and $_.properties.functionAlias })
        Workbooks      = & $items $StandIn.workbooks
        Dcrs           = & $items $StandIn.dataCollectionRules
        Playbooks      = & $items $StandIn.logicApps
    }
}

Export-ModuleMember -Function Get-TableMigrationStandIn, Get-TableMigrationStandInAnswer, ConvertTo-TableMigrationContent

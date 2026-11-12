#Requires -Version 7.6

<#
.SYNOPSIS
    Header text for table columns, by column name.

.DESCRIPTION
    Defines $script:ColumnLabels for the Blueprint renderer when the module loads.

.NOTES
    File:         Modules/iSOCBlueprint/Private/Render/Data/ColumnLabels.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-12
    Version:      0.1.0
    Last Updated: 2026-11-12
    Requires:     PowerShell 7.6+

    This file defines a lookup table rather than running.
#>


# A column named after a raw property (Gb30d, MonthlyCost, LastFailureUtc)
# reads as words in a table header: the names below as written, any other
# CamelCase name split into words. A name with a space or in one word keeps
# its text.
$script:ColumnLabels = @{
    Gb30d = 'GB ({lookback-d})'; Gb7d = 'GB ({recent-d})'; Gb90d = 'GB ({lookback-d})'; GbRead = 'GB read'; Last24hGB = 'GB (24h)'
    BillableLast24hGB = 'Billable GB (24h)'; BilledSizeGB = 'Billed GB ({lookback-d})'; SizeMB = 'Size (MB, {lookback-d})'
    Data7d = 'Data ({recent-d})'; Failed7d = 'Failed ({lookback-d})'; Records30d = 'Records ({lookback-d})'; Records7d = 'Records ({recent-d})'
    Rows7d = 'Rows ({recent-d})'; Rows12d = 'Rows ({lookback-d})'; Rows14d = 'Rows ({lookback-d})'; Runs7d = 'Runs ({lookback-d})'; Last24h = 'Last 24h'
    FPRate = 'FP rate'; LastFailureUtc = 'Last failure (UTC)'; EventID = 'Event ID'; OSType = 'OS type'; OSVersion = 'OS version'
    AMACount = 'AMA machines'; MMACount = 'MMA machines'; ResourceId = 'Resource ID'; SubscriptionId = 'Subscription ID'
    WriteAccessResourceId = 'Write access resource ID'; TargetsWs = 'Targets workspace'; SkuName = 'SKU'
    DeltaVsCurrent = 'Change vs current'; AvgMinsToClose = 'Average minutes to close'; ClosedWithinHour = 'Closed within an hour'
    SignIn = 'Sign-in'; SearchRestore = 'Search and restore'; SubTechniques = 'Sub-techniques'; StixType = 'STIX type'
    DuplicateEventIds = 'Duplicate event IDs'; FirstPartyAlerts = 'First-party alerts'; LakeOnlyDays = 'Lake-only days'
    AnalyticsDays = 'Analytics days'; RetentionDays = 'Retention (days)'; TotalDays = 'Total days'; HasTransform = 'Transform'
    MonthlyCost = 'Monthly cost'; ProjectedMonthlyCost = 'Projected monthly cost'
    Alerts7d = 'Alerts ({recent-d})'; LogCount = 'Records ({lookback-d})'; RecordCount = 'Records ({lookback-d})'; Events = 'Events ({lookback-d})'
    LastIngested = 'Last ingested (UTC)'; Created = 'Created (UTC)'; Updated = 'Updated (UTC)'; LastModified = 'Last modified (UTC)'
    FirstSeen = 'First seen (UTC)'; LastSeen = 'Last seen (UTC)'
}

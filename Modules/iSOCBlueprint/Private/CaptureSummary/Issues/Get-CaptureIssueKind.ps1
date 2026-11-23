#Requires -Version 7.6

<#
.SYNOPSIS
    Sort a capture's error: 'Permission', 'NotAvailable' or 'Error'.

.NOTES
    File:         Modules/iSOCBlueprint/Private/CaptureSummary/Issues/Get-CaptureIssueKind.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-16
    Version:      0.1.2
    Last Updated: 2026-11-23
    Component:    iSOC Blueprint, Capture reporting
    Requires:     PowerShell 7.6+

    This file defines a function rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-CaptureIssueKind {
    <#
    .SYNOPSIS
        Sort a capture's error: 'Permission', 'NotAvailable' or 'Error'.

    .DESCRIPTION
        A refusal (401, 403, AuthorizationFailed and the like) is Permission.
        A query naming a column its tables lack ("Failed to resolve scalar
        expression") is Error: the query's fault, to be fixed. A table or
        endpoint the workspace does not have (KQL "Failed to resolve table or
        column expression", 404, an unregistered provider or resource type)
        is NotAvailable. A timeout, throttling or service error is Error. A
        bare 400 with nothing more is NotAvailable: the collector's queries
        are parsed in its tests, so a refused query is almost always one
        that names a table this workspace lacks.

    .PARAMETER Message
        The capture's error message.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowEmptyString()] [string] $Message)

    $permission = '\b40[13]\b|Forbidden|Unauthori[sz]ed|AuthorizationFailed|AuthorizationPermissionMismatch|Authorization_RequestDenied|does not have (authorization|permission)|Insufficient privileges|InsufficientPermissions|AccessDenied|Access denied'
    # A query naming a column its tables do not have is the query's fault, not
    # the workspace's: KQL says "scalar expression" for a missing column and
    # "table or column expression" for a missing table.
    $queryBug = 'Failed to resolve (scalar|column) expression'
    $missing = 'Failed to resolve table|could not be resolved|\b404\b|Not ?Found|PathNotFound|ResourceNotFound|NoRegisteredProviderFound|InvalidResourceType|not (served|supported|available|enabled)|FeatureNotEnabled|does not exist'
    $failure = 'time(d)? ?out|exceeded|too large|throttl|\b429\b|TooManyRequests|\b50\d\b|InternalServerError|ServiceUnavailable|GatewayTimeout'
    if ($Message -match $permission) { return 'Permission' }
    if ($Message -match $queryBug) { return 'Error' }
    if ($Message -match $missing) { return 'NotAvailable' }
    if ($Message -match $failure) { return 'Error' }
    if ($Message -match 'BadRequest|\b400\b') { return 'NotAvailable' }
    'Error'
}

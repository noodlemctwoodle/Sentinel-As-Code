#Requires -Version 7.2

<#
.SYNOPSIS
    The Graph detectionRule contract: the values the service accepts and
    how the retired fields map to the current ones.

.DESCRIPTION
    Copied from Get-DetectionContract (Deploy/content/Deploy-DefenderDetections.ps1).
    Microsoft replaced the original custom detection fields on 2026-10-01:
    isEnabled became status, schedule.period became the ISO 8601
    schedule.frequency, alertTemplate.category and mitreTechniques became
    alertTemplate.tactics, impactedAssets became entityMappings and
    responseActions became automatedActions. The new entity mappings and
    automated actions name query result columns (DeviceId, AccountSid)
    where the old shape named identifier tokens (deviceId, accountSid).

.NOTES
    File:         Modules/iSOCDeployments/Private/ContentTypes/DefenderDetection/Get-iSOCDefenderDetectionContract.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-11-03
    Version:      0.1.0
    Last Updated: 2026-11-03
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Per-parameter detail
    lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Get-iSOCDefenderDetectionContract {
    <#
    .SYNOPSIS
        Return the contract tables the converters and the validator share.

    .DESCRIPTION
        Built on each call rather than kept in module state; the tables are
        small.

    .OUTPUTS
        [System.Collections.Specialized.OrderedDictionary]
        ValidDetectionSeverities, ValidDetectionStatuses,
        ValidDetectionTactics, ValidDetectionFrequencyHours,
        EntityMappingCollections, AutomatedActionRequiredColumns,
        LegacyResponseActionMap and LegacyMultiIdentifierColumns.

    .EXAMPLE
        (Get-iSOCDefenderDetectionContract).ValidDetectionTactics
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param()

    [ordered]@{
        ValidDetectionSeverities     = @('informational', 'low', 'medium', 'high')
        ValidDetectionStatuses       = @('enabled', 'disabled')
        ValidDetectionTactics        = @(
            'Reconnaissance', 'ResourceDevelopment', 'InitialAccess', 'Execution', 'Persistence',
            'PrivilegeEscalation', 'DefenseEvasion', 'CredentialAccess', 'Discovery', 'LateralMovement',
            'Collection', 'CommandAndControl', 'Exfiltration', 'Impact'
        )
        # Rule frequencies the service runs, as whole hours.
        ValidDetectionFrequencyHours = @(1, 3, 12, 24)

        EntityMappingCollections     = @(
            'accounts', 'amazonResources', 'azureResources', 'cloudApplications', 'dns', 'files',
            'googleCloudResources', 'hosts', 'ips', 'mailboxes', 'mailClusters', 'mailMessages',
            'oAuthApplications', 'processes', 'registryValues', 'securityGroups', 'urls'
        )

        # automatedActions member -> the column properties every entry needs.
        AutomatedActionRequiredColumns = @{
            allowFiles                   = @()
            blockFiles                   = @()
            collectInvestigationPackages = @('deviceIdColumn')
            disableUsers                 = @('accountSidColumn')
            forceUserPasswordResets      = @('accountSidColumn')
            hardDeleteEmails             = @('networkMessageIdColumn', 'recipientColumn')
            initiateInvestigations       = @('deviceIdColumn')
            isolateDevices               = @('deviceIdColumn', 'isolationType')
            markUsersAsCompromised       = @('accountObjectIdColumn')
            moveEmailsToDeletedItems     = @('networkMessageIdColumn', 'recipientColumn')
            moveEmailsToInbox            = @('networkMessageIdColumn', 'recipientColumn')
            moveEmailsToJunk             = @('networkMessageIdColumn', 'recipientColumn')
            restrictAppExecutions        = @('deviceIdColumn')
            runAntivirusScans            = @('deviceIdColumn')
            softDeleteEmails             = @('networkMessageIdColumn', 'recipientColumn')
            stopAndQuarantineFiles       = @('deviceIdColumn', 'sha1Column')
        }

        # Old responseActions @odata.type -> new automatedActions member and the
        # column property its single identifier fills.
        LegacyResponseActionMap      = @{
            markUserAsCompromisedResponseAction       = @{ Member = 'markUsersAsCompromised'; Column = 'accountObjectIdColumn' }
            forceUserPasswordResetResponseAction      = @{ Member = 'forceUserPasswordResets'; Column = 'accountSidColumn' }
            disableUserResponseAction                 = @{ Member = 'disableUsers'; Column = 'accountSidColumn' }
            collectInvestigationPackageResponseAction = @{ Member = 'collectInvestigationPackages'; Column = 'deviceIdColumn' }
            runAntivirusScanResponseAction            = @{ Member = 'runAntivirusScans'; Column = 'deviceIdColumn' }
            initiateInvestigationResponseAction       = @{ Member = 'initiateInvestigations'; Column = 'deviceIdColumn' }
            restrictAppExecutionResponseAction        = @{ Member = 'restrictAppExecutions'; Column = 'deviceIdColumn' }
            isolateDeviceResponseAction               = @{ Member = 'isolateDevices'; Column = 'deviceIdColumn' }
            hardDeleteResponseAction                  = @{ Member = 'hardDeleteEmails'; Column = $null }
            softDeleteResponseAction                  = @{ Member = 'softDeleteEmails'; Column = $null }
            moveToJunkResponseAction                  = @{ Member = 'moveEmailsToJunk'; Column = $null }
            moveToInboxResponseAction                 = @{ Member = 'moveEmailsToInbox'; Column = $null }
            moveToDeletedItemsResponseAction          = @{ Member = 'moveEmailsToDeletedItems'; Column = $null }
            stopAndQuarantineFileResponseAction       = @{ Member = 'stopAndQuarantineFiles'; Column = $null }
            blockFileResponseAction                   = @{ Member = 'blockFiles'; Column = $null }
            allowFileResponseAction                   = @{ Member = 'allowFiles'; Column = $null }
        }

        # Identifier tokens that name a specific column property when an old action
        # carried several comma-separated identifiers.
        LegacyMultiIdentifierColumns = @{
            networkMessageId      = 'networkMessageIdColumn'
            recipientEmailAddress = 'recipientColumn'
            deviceId              = 'deviceIdColumn'
            sha1                  = 'sha1Column'
            sha256                = 'sha256Column'
        }
    }
}

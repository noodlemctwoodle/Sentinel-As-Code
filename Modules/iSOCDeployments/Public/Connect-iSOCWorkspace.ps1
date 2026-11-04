#Requires -Version 7.2

<#
.SYNOPSIS
    Connect-iSOCWorkspace: choose the workspace every other command works on.

.DESCRIPTION
    Replaces Connect-AzureEnvironment from Modules/Sentinel.Common, which
    every deployer and the drift script called with -ResourceGroup,
    -Workspace, -Region and -IsGov. The region and the cloud now come from
    the workspace and the Az sign-in, and the module signs nothing in on its
    own (MIGRATION.md edits E2 and E6).

.NOTES
    File:         Modules/iSOCDeployments/Public/Connect-iSOCWorkspace.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-23
    Version:      0.2.0
    Last Updated: 2026-11-04
    Requires:     PowerShell 7.2+

    Needs Az.Accounts when it runs. The module checks for it at that point
    (Assert-iSOCPrerequisite) instead of in #Requires, so it imports
    without it.

    This file defines functions rather than running. Per-parameter and
    per-example detail lives on the function's own help block.
#>

# Keeps the file help above from being read as the help of the function below.

function Connect-iSOCWorkspace {
    <#
    .SYNOPSIS
        Point iSOCDeployments at one workspace through the current Azure
        sign-in.

    .DESCRIPTION
        Reads the workspace, to confirm it exists and to learn its id and
        region, and checks that the playbook resource group exists when
        playbooks go to a group of their own. The result is the context every
        other command uses when it is not given -Context, until the next
        Connect-iSOCWorkspace.

        Sign in first with Connect-AzAccount; in a pipeline the
        AzurePowerShell task or azure/login does it. The cloud is the
        sign-in's: the ARM and Graph hosts are read from its environment, so
        US Government needs no switch.

        Nothing in Azure changes. With -SubscriptionId the Az sign-in moves
        to that subscription, as Set-AzContext would. Nothing the command
        logs names the subscription or the workspace id, so the log can be
        public.

    .PARAMETER ResourceGroup
        The resource group holding the workspace.

    .PARAMETER WorkspaceName
        The Log Analytics workspace Sentinel runs on.

    .PARAMETER SubscriptionId
        The subscription holding the workspace. Defaults to the sign-in's
        current subscription.

    .PARAMETER PlaybookResourceGroup
        The resource group playbooks deploy to. Defaults to -ResourceGroup.

    .OUTPUTS
        [pscustomobject] The iSOCDeployments.Context. Its properties cannot be
        changed.

    .EXAMPLE
        Connect-AzAccount
        Connect-iSOCWorkspace -ResourceGroup rg-sentinel -WorkspaceName law-sentinel

        Signs in, then connects to the workspace in the current subscription.

    .EXAMPLE
        $ctx = Connect-iSOCWorkspace -SubscriptionId $subscriptionId -ResourceGroup rg-sentinel -WorkspaceName law-sentinel -PlaybookResourceGroup rg-playbooks

        Connects to a workspace in another subscription whose playbooks live
        in their own resource group, and keeps the context to pass on.
    #>
    [CmdletBinding()]
    [OutputType('iSOCDeployments.Context')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ResourceGroup,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [Alias('Workspace')]
        [string] $WorkspaceName,

        [ValidatePattern('^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')]
        [string] $SubscriptionId,

        [string] $PlaybookResourceGroup
    )

    Assert-iSOCPrerequisite -Step Connect

    $session = Get-iSOCAzSession -SubscriptionId $SubscriptionId
    $subscription = $session.SubscriptionId

    $workspacePath = "/subscriptions/$subscription/resourceGroups/$ResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName"
    $workspace = Invoke-iSOCRestRequest -Method GET -Path $workspacePath -ApiVersion (Get-iSOCApiVersion OperationalInsights) -AllowNotFound
    if (-not $workspace) {
        throw "Workspace '$WorkspaceName' was not found in resource group '$ResourceGroup' of the signed-in subscription."
    }

    $playbookGroup = if ($PlaybookResourceGroup) { $PlaybookResourceGroup } else { $ResourceGroup }
    if ($playbookGroup -ne $ResourceGroup) {
        $group = Invoke-iSOCRestRequest -Method GET -Path "/subscriptions/$subscription/resourceGroups/$playbookGroup" -ApiVersion (Get-iSOCApiVersion ResourceGroups) -AllowNotFound
        if (-not $group) {
            throw "Playbook resource group '$playbookGroup' does not exist. Create it with the Bicep template (playbookRgName in main.bicep) or in the Azure portal first."
        }
    }

    $context = New-iSOCContext -Value @{
        TenantId              = $session.TenantId
        SubscriptionId        = $subscription
        ResourceGroup         = $ResourceGroup
        WorkspaceName         = $WorkspaceName
        WorkspaceResourceId   = $workspacePath
        WorkspaceId           = [string](Get-iSOCPropertyValue -InputObject $workspace -Path 'properties.customerId')
        Region                = [string](Get-iSOCPropertyValue -InputObject $workspace -Path 'location')
        PlaybookResourceGroup = $playbookGroup
        Environment           = $session.Environment
        IsGov                 = $session.IsGov
        ArmUrl                = $session.ArmUrl
        GraphUrl              = $session.GraphUrl
        Account               = $session.Account
    }
    $script:iSOCContext = $context

    $where = if ($playbookGroup -ne $ResourceGroup) { "; playbooks deploy to resource group $playbookGroup" } else { '' }
    Write-iSOCLog "Connected to workspace $WorkspaceName in resource group $ResourceGroup ($($session.Environment))$where." -Level Success
    $context
}

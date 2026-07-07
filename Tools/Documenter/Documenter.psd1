@{
    # Pinned module versions for the Sentinel Documenter. Both the collector
    # (Export-SentinelInventory.ps1) and the renderer
    # (Convert-SentinelInventoryToMarkdown.ps1) honour these pins.
    #
    # The collector imports the Az.* modules; the renderer is pure file I/O
    # and only needs powershell-yaml.
    #
    # Bumping a pin is a one-line PR that re-runs the validation gate against
    # the new version. Keep the workflow cache key in sync with the tuple
    # below so a version bump invalidates the cache cleanly.

    Modules = @{
        'Az.Accounts'           = '3.0.4'
        'Az.SecurityInsights'   = '3.1.2'
        'Az.OperationalInsights'= '3.2.0'
        'Az.Monitor'            = '5.2.1'
        'Az.Resources'          = '7.4.0'
        'Az.LogicApp'           = '1.7.0'
        'powershell-yaml'       = '0.4.12'
    }

    # API versions used across the documenter. Centralised so a single bump
    # propagates through every Invoke-AzRestMethod call.
    ApiVersions = @{
        Sentinel              = '2024-09-01'         # GA — covers most artefacts
        SentinelPreview       = '2024-10-01-preview' # Content Hub product packages, summary rules, pricings
        OperationalInsights   = '2025-02-01'         # Workspace, replication, network ACL fields
        Tables                = '2023-09-01'         # Table plan, retention, archive
        DataCollection        = '2023-03-11'         # DCRs, DCEs, DCRA full JSON
    }

    # Author / repo metadata — referenced by Documenter-References.md generator and the
    # banner line in every produced Markdown file.
    Author     = 'noodlemctwoodle'
    Repository = 'Sentinel-As-Code'
    Component  = 'Sentinel Documenter'
    Version    = '0.1.0'
}

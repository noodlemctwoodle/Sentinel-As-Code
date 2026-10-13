@{
    # Reference record of the module versions and API versions the
    # Blueprint is built and tested against. Nothing reads this file at run
    # time: the collector carries its own copy of the API versions (see
    # Blueprint-References.md for why), and the pipelines pin their module
    # versions themselves. Keep it in step with both by hand.
    #
    # The collector imports the Az.* modules; the renderer is pure file I/O
    # and only needs powershell-yaml. Test-iSOCBlueprintPrerequisite checks
    # what a machine has.

    Modules = @{
        'Az.Accounts'           = '3.0.4'
        'Az.SecurityInsights'   = '3.1.2'
        'Az.OperationalInsights'= '3.2.0'
        'Az.Monitor'            = '5.2.1'
        'Az.Resources'          = '7.4.0'
        'Az.LogicApp'           = '1.7.0'
        'powershell-yaml'       = '0.4.12'
    }

    # API versions used across the blueprint. Centralised so a single bump
    # propagates through every Invoke-AzRestMethod call.
    ApiVersions = @{
        Sentinel              = '2024-09-01'         # GA — covers most artefacts
        SentinelPreview       = '2024-10-01-preview' # Alert rules (subTechniques), Content Hub product packages, summary rules, pricings
        OperationalInsights   = '2025-02-01'         # Workspace, replication, network ACL fields
        Tables                = '2025-02-01'         # Table plan, retention, tableSubType; falls back to 2023-09-01
        DataCollection        = '2023-03-11'         # DCRs, DCEs, DCRA full JSON
    }

    # Author and repository metadata.
    Author     = 'noodlemctwoodle'
    Repository = 'Sentinel-As-Code'
    Component  = 'iSOC Blueprint'
}

# iSOCDeployments test fixtures

`repo/` is a minimal Sentinel-As-Code repository: it has a `Content/`
folder, so `Resolve-iSOCRepoPath` treats it as a repository root, and one
folder per content type the module has ported so far.

| Path | Used for |
| --- | --- |
| `repo/Content/AnalyticalRules/Identity/ScheduledRule.yaml` | A Scheduled rule with every optional field the request builder passes through, an upper-case id, the short `gt` operator and sub-techniques |
| `repo/Content/AnalyticalRules/Identity/NrtRule.yaml` | An NRT rule, disabled in the file, with suppression set |
| `repo/Content/AnalyticalRules/Community/CommunityRule.yml` | A rule under a Community folder, with the `.yml` extension and the long operator spelling |
| `repo/Content/AnalyticalRules/MissingFields.yaml` | A Scheduled rule without its schedule, which validation rejects |
| `repo/Content/AnalyticalRules/Broken.yaml` | A file that does not parse |
| `repo/Content/AnalyticalRules/README.md` | A file the rule patterns must skip |
| `repo/Content/Parsers/Identity/FixtureSignInParser.yaml` | A parser with a category default, function parameters and the alias `FixtureSignIns` |
| `repo/Content/Parsers/MissingAlias.yaml` | A parser without its `functionAlias`, which validation rejects and the inventory leaves out |
| `repo/Content/HuntingQueries/SigninLogs/FixtureHunt.yaml` | A hunting query with tactics, a sub-technique and its own tags, calling the fixture parser and two watchlists, one of them not in the repository |
| `repo/Content/HuntingQueries/SigninLogs/NoQuery.yaml` | A hunting query without its query |
| `repo/Content/Watchlists/vipUsers/` | A complete watchlist (`watchlist.json` and `data.csv`) |
| `repo/Content/Watchlists/noData/` | A watchlist without its `data.csv`, and without a description or provider |
| `repo/Content/Watchlists/emptyFolder/` | A watchlist folder without a `watchlist.json` |
| `repo/Content/Playbooks/Module/ZuluBase.json`, `AlphaCaller.json` | Two module playbooks, `AlphaCaller` calling `ZuluBase`, so the order puts the one called first |
| `repo/Content/Playbooks/Incident/FixtureIncident.json` | A playbook with a parameters file beside it |
| `repo/Content/Playbooks/NotArm.json` | A JSON file that is not an ARM template, which validation rejects |
| `repo/Content/Playbooks/Template/FixtureTemplate.json` | A file under a `Template` folder, which the reader leaves out |
| `repo/Content/Workbooks/FixtureOverview/` | A workbook with a `metadata.json` naming it and pinning its id |
| `repo/Content/Workbooks/ArmWrapped/` | A workbook wrapped in an ARM template, with no `metadata.json` |
| `repo/Content/Workbooks/NoTemplate/` | A workbook folder without a `workbook.json` |
| `repo/Content/AutomationRules/FixtureAutoClose.json` | A complete automation rule, with order 0 |
| `repo/Content/AutomationRules/MissingActions.json` | An automation rule without its actions |
| `repo/Content/SummaryRules/FixtureSummary.json` | A summary rule with every optional field |
| `repo/Content/SummaryRules/BadBinSize.json`, `NoSuffix.json` | Summary rules with a bin size Log Analytics refuses, and a destination that is not a custom table |
| `repo/Content/DefenderCustomDetections/Endpoint/FixtureEncodedPowerShell.yaml` | A Defender detection in the current Graph shape with every optional part: description, mixed-case severity, entity mappings, custom details, an automated action, device groups and incident configuration |
| `repo/Content/DefenderCustomDetections/Identity/FixtureLegacySpray.yaml` | A Defender detection written with the fields Graph retired on 2026-10-01, which the reader translates |
| `repo/Content/DefenderCustomDetections/Email/FixtureExistingNoId.yaml` | A Defender detection without an `id`: updated when the tenant has it, failed when it does not |
| `repo/Content/DefenderCustomDetections/Email/InvalidFrequency.yaml` | A Defender detection with two problems, a frequency the service does not run and an unknown tactic |

`contenthub/standin.json` is a synthetic Content Hub for
`ContentHub.Tests.ps1`, served by `_helpers/ContentHubStandIn.psm1`: five
solutions (one behind the catalogue, one current, one new with no package,
one the workspace lists but the catalogue does not report installed, one
not asked for), rule templates for every path the rule step takes (new,
current, newer, changed in the workspace, matched by name only,
deprecated, filtered by severity, NRT, refused three ways, and with no
rule in them), workbook templates for every path the workbook step takes,
automation rule and hunting query templates (the hunting queries on two
pages), the workspace's rules and workbook metadata, and the display names
whose writes it refuses.

The fixtures are synthetic and name no real tenant, workspace or
organisation. The repository-wide content suites (`Tests/Test-*Yaml.Tests.ps1`)
and the dependency manifest read `Content/` at the repository root only,
so nothing here is deployed or checked as real content.

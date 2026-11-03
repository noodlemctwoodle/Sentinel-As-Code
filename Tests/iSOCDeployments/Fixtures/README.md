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

The fixtures are synthetic and name no real tenant, workspace or
organisation. The repository-wide content suites (`Tests/Test-*Yaml.Tests.ps1`)
and the dependency manifest read `Content/` at the repository root only,
so nothing here is deployed or checked as real content.

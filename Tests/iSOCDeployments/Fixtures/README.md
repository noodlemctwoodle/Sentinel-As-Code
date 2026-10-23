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

The fixtures are synthetic and name no real tenant, workspace or
organisation. The repository-wide content suites (`Tests/Test-*Yaml.Tests.ps1`)
and the dependency manifest read `Content/` at the repository root only,
so nothing here is deployed or checked as real content.

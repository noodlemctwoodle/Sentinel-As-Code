# Pester Tests

Unit tests for PowerShell scripts in this repo use [Pester 5](https://pester.dev),
the standard PowerShell testing framework. Tests live alongside the scripts
they cover under [`Tests/`](../../Tests) and exercise pure functions in
isolation — no Azure connectivity, no live workspaces, no side effects on
the repo working tree.

| What | Where |
| --- | --- |
| Test files | [`Tests/`](../../Tests) - 78 suites total: 14 root-level `<ScriptName>.Tests.ps1` (content validation, plus one per script outside the modules), 28 under [`Tests/iSOCBlueprint/`](../../Tests/iSOCBlueprint) and 36 under [`Tests/iSOCDeployments/`](../../Tests/iSOCDeployments) |
| Convention | Pester 5+ discovery model (`Describe` / `Context` / `It` / `BeforeAll`) |
| Isolation | `$TestDrive` for temp files; AST extraction so source scripts never run their `Main` |
| PR-gate entrypoint | [`Tools/Invoke-PRValidation.ps1`](../../Tools/Invoke-PRValidation.ps1) - runs every suite, emits NUnit XML, exits non-zero when a test fails, a `BeforeAll` or `AfterAll` block fails, or a suite cannot be loaded |
| GitHub Actions | [`.github/workflows/pr-validation.yml`](../../.github/workflows/pr-validation.yml) — triggers on `pull_request` to `main` |
| ADO pipeline | [`Pipelines/Sentinel-PR-Validation.yml`](../../Pipelines/Sentinel-PR-Validation.yml) — wired as a build-validation policy on `main` |

## Prerequisites

| Component | Minimum | Install |
| --- | --- | --- |
| PowerShell | 7.6+ | [pwsh download](https://github.com/PowerShell/PowerShell/releases) |
| Pester | 5.0+ | `Install-Module -Name Pester -Force -SkipPublisherCheck` |
| `powershell-yaml` | any | Auto-installed by tests when needed |

CI does not rely on "latest" for either module. The GitHub `validate` job
installs both through the composite action
[`.github/actions/setup-pwsh-modules`](../../.github/actions/setup-pwsh-modules/action.yml),
which pins the exact versions the workflow declares in its top-level `env`
block: `PESTER_VERSION: 5.7.1` and `YAML_VERSION: 0.4.12`. Match those pins
locally if you are chasing a "passes locally, fails in CI" discrepancy.

Verify Pester is available:

```powershell
Get-Module -ListAvailable Pester | Select-Object Name, Version
```

## Running tests

### As the PR gate runs them

```powershell
./Tools/Invoke-PRValidation.ps1
```

`Invoke-PRValidation.ps1` is the single entrypoint both pipelines call. It
installs Pester + powershell-yaml if missing, runs every suite under
`Tests/`, writes a NUnit-2.5 XML report to `test-results/pester-results.xml`,
and exits non-zero on any failure. Pester counts three kinds of failure
apart and the gate fails on each: a failed test; a failed `BeforeAll` or
`AfterAll` block (its tests can still pass); and a suite that cannot be
loaded, because its `BeforeDiscovery` or top-level code throws or it does
not parse, which leaves its tests undiscovered rather than failed. The
summary counts each, and the log names every failed suite and block with
its error. Use this locally to mirror exactly what the PR check does.

Pass `-InstallModules:$false` to skip the auto-install when you have the
modules already pinned via your profile, and `-TestNameFilter '<pattern>'`
to scope down to a specific Describe / Context.

### All tests directly via Pester

```powershell
Invoke-Pester -Path Tests -CI
```

`-CI` exits non-zero on any failure and is the right flag for pipelines and
local pre-commit hooks. Equivalent to `Invoke-PRValidation.ps1` but without
the NUnit XML output.

### A specific test file

```powershell
Invoke-Pester -Path Tests/iSOCDeployments/Drift.Tests.ps1 -CI
```

### A specific Describe block

```powershell
Invoke-Pester -Path Tests/iSOCDeployments/Drift.Tests.ps1 -FullName '*Update-iSOCAnalyticsRuleYaml*'
```

### Verbose / detailed output

```powershell
Invoke-Pester -Path Tests/iSOCDeployments/Drift.Tests.ps1 -Output Detailed
```

`-Output Detailed` shows every individual `It` block as it runs. The default
(`-Output Normal`) shows just per-file pass/fail and any failure details.

### Code coverage

```powershell
Invoke-Pester -Path Tests/iSOCDeployments/Drift.Tests.ps1 `
    -CodeCoverage Modules/iSOCDeployments/Private/Drift/*.ps1 `
    -Output Detailed
```

Reports which lines of the source script each test exercised.

## PR-validation gate

Every pull request to `main` must pass the Pester suite before it can merge.
The gate is enforced on both platforms:

| Platform | Workflow / pipeline | Triggered by |
| --- | --- | --- |
| GitHub Actions | [`.github/workflows/pr-validation.yml`](../../.github/workflows/pr-validation.yml) | `pull_request` events on `main`, `push` to `main` (CI baseline), and `workflow_dispatch`. There is no `paths` / `paths-ignore` filter, so every job runs on every trigger |
| Azure DevOps | [`Pipelines/Sentinel-PR-Validation.yml`](../../Pipelines/Sentinel-PR-Validation.yml) | The `pr:` trigger inside the YAML; required as a build-validation policy on `main` |

Both call the same [`Tools/Invoke-PRValidation.ps1`](../../Tools/Invoke-PRValidation.ps1)
entrypoint, so the validation logic stays in one place. The pipelines just
handle environment setup, NUnit-XML publishing, and merge gating.

### What gets validated

The GitHub workflow ([`.github/workflows/pr-validation.yml`](../../.github/workflows/pr-validation.yml))
runs five parallel jobs, each surfacing as its own status check the
ruleset can require independently:

| Job | What | Auth | Setup |
| --- | --- | --- | --- |
| `validate` | Every Pester suite under `Tests/` (~6,000 assertions; grows with content) | None | Already wired |
| `bicep-build` | `az bicep build` against every `Infra/**/*.bicep` | None | Already wired |
| `arm-validate` | `Test-AzResourceGroupDeployment` (a template-validation call, not a What-If) against every playbook under `Content/Playbooks/` (`.bicep`, and any ARM `.json`) | OIDC | One-off: see [PR-Validation-Setup.md](../Deploy/PR-Validation-Setup.md) |
| `kql-validate` | KQL syntax check via the Microsoft.Azure.Kusto.Language parser across all rule queries | None | Already wired |
| `dependency-manifest` | `Test-iSOCDependencyManifest` - fails if `dependencies.json` drifts from discovery | None | Already wired. See [Dependency Manifest](../Tools/Dependency-Manifest.md) |

#### Pester suites covered by `validate`

The `validate` job points Pester at the whole `Tests/` tree (`Run.Path` is
set to the folder, not an explicit file list), so every suite below runs in
the gate, including the `Tests/iSOCBlueprint/` and `Tests/iSOCDeployments/` suites and the Copilot /
workbook-export suites.

| Suite | File | Coverage |
| --- | --- | --- |
| Analytical rule YAML schema | [`Tests/Test-AnalyticalRuleYaml.Tests.ps1`](../../Tests/Test-AnalyticalRuleYaml.Tests.ps1) | 193 analytical rules + 51 hunting queries × per-file schema; cross-file `id` uniqueness |
| Dependency manifest | [`Tests/Test-DependencyManifest.Tests.ps1`](../../Tests/Test-DependencyManifest.Tests.ps1) | `dependencies.json` shape; per-entry path resolution; watchlist + function alias resolution |
| Defender custom detections | [`Tests/Test-DefenderDetectionYaml.Tests.ps1`](../../Tests/Test-DefenderDetectionYaml.Tests.ps1) | Per file: parses, lowercase kebab-case `id`, no retired Graph field names, passes the module's `Test-iSOCDefenderDetection` (which also places each technique under a tactic it belongs to in MITRE ATT&CK 18.1), every mapped column appears in the query; cross-file unique `displayName` and `id` (the `-ForEach` count tracks the file tree) |
| Watchlists | [`Tests/Test-WatchlistJson.Tests.ps1`](../../Tests/Test-WatchlistJson.Tests.ps1) | JSON schema + sibling CSV header invariants; cross-directory alias uniqueness |
| Automation rules | [`Tests/Test-AutomationRuleJson.Tests.ps1`](../../Tests/Test-AutomationRuleJson.Tests.ps1) | Action types, trigger logic, propertyValues array shape; cross-file id uniqueness |
| Summary rules | [`Tests/Test-SummaryRuleJson.Tests.ps1`](../../Tests/Test-SummaryRuleJson.Tests.ps1) | binSize enum, destinationTable suffix, KQL restriction patterns |
| Parsers | [`Tests/Test-ParserYaml.Tests.ps1`](../../Tests/Test-ParserYaml.Tests.ps1) | Required fields + KQL-identifier validation; cross-file functionAlias uniqueness |
| Workbooks | [`Tests/Test-WorkbookJson.Tests.ps1`](../../Tests/Test-WorkbookJson.Tests.ps1) | ARM-vs-gallery format detection; cross-directory GUID uniqueness for ARM workbooks |
| Playbooks (structural) | [`Tests/Test-PlaybookArm.Tests.ps1`](../../Tests/Test-PlaybookArm.Tests.ps1) | Every Bicep playbook compiled (one run of the Bicep CLI) with no error or warning, then each playbook's ARM template held to the structure + workflow trigger/action presence |
| Helper module self-test | [`Tests/Test-ImportScriptFunctions.Tests.ps1`](../../Tests/Test-ImportScriptFunctions.Tests.ps1) | AST extractor synthetic + real-repo round-trip |
| PR gate | [`Tests/Test-InvokePRValidation.Tests.ps1`](../../Tests/Test-InvokePRValidation.Tests.ps1) | `Tools/Invoke-PRValidation.ps1` run against throwaway repositories: it passes when every suite passes, and fails, naming what broke, for a failed test, a suite whose discovery throws, a suite that does not parse and a failed `AfterAll` |
| PR template validator | [`Tests/Test-PullRequestTemplate.Tests.ps1`](../../Tests/Test-PullRequestTemplate.Tests.ps1) | `Remove-MarkdownComment`, `Get-PullRequestSection`, `Test-PullRequestTemplateBody` (required-section + tick-box rules for the PR description) |
| Copilot customisations | [`Tests/Test-CopilotCustomisations.Tests.ps1`](../../Tests/Test-CopilotCustomisations.Tests.ps1) | Frontmatter parses, required keys present, display-name prefix, `applyTo` glob hygiene, and a cross-reference link checker across `.github/agents/`, `.github/instructions/`, `.github/prompts/`, `.github/copilot-instructions.md`, and `AGENTS.md` |
| PowerShell 7.6 floor | [`Tests/Test-PowerShellVersion.Tests.ps1`](../../Tests/Test-PowerShellVersion.Tests.ps1) | Every tracked `.ps1` and `.psm1` opens with `#Requires -Version 7.6`, reads as 7.6 to the PowerShell parser and has one `Requires: PowerShell 7.6+` key in `.NOTES`; both module manifests declare `PowerShellVersion = '7.6'`; no workflow, composite action or ADO pipeline runs a step in Windows PowerShell; every Azure Automation runtime environment is PowerShell 7.6, every PowerShell runbook runs on one and the DCR inventory pipelines link the runbook to it; no file other than `CHANGELOG.md` and `MIGRATION.md` states a PowerShell requirement below 7.6 |
| Blueprint renderer | [`Tests/iSOCBlueprint/Convert-SentinelInventoryToMarkdown.Tests.ps1`](../../Tests/iSOCBlueprint/Convert-SentinelInventoryToMarkdown.Tests.ps1) | Renders the Blueprint Markdown from the `Tests/iSOCBlueprint/Fixtures/sample/_raw` JSON corpus and asserts expected output plus empty-state safety |
| Blueprint gap engine | [`Tests/iSOCBlueprint/Get-SentinelGap.Tests.ps1`](../../Tests/iSOCBlueprint/Get-SentinelGap.Tests.ps1) | Drives the gap-analysis engine against a deliberately-broken fixture and asserts each gap rule fires |
| Blueprint REST wrapper | [`Tests/iSOCBlueprint/Invoke-SentinelRest.Tests.ps1`](../../Tests/iSOCBlueprint/Invoke-SentinelRest.Tests.ps1) | URL construction inside `Invoke-SentinelRest` (api-version appending, existing query-string handling) |
| Blueprint section model | [`Tests/iSOCBlueprint/Section-Model.Tests.ps1`](../../Tests/iSOCBlueprint/Section-Model.Tests.ps1) | The Markdown-to-section-model converter, the Mermaid chart parser (every chart kind) and the renderer's `sections/*.json` validated against the schemas, with both output formats |
| Blueprint SharePoint site | [`Tests/iSOCBlueprint/SharePoint-Site.Tests.ps1`](../../Tests/iSOCBlueprint/SharePoint-Site.Tests.ps1) | Section families, section-model-to-page conversion (charts as chart segments, the stand-in tables), the publish planners, the maturity history helper, the publisher's SharePoint steps (app catalog, section pages with the chart web part, dashboard page, navigation) against stand-in PnP functions, and an offline site-bundle build from the fixture, from the section model and from Markdown alone (no SharePoint or PnP needed) |
| Blueprint SharePoint PnP calls | [`Tests/iSOCBlueprint/SharePoint-PnPCalls.Tests.ps1`](../../Tests/iSOCBlueprint/SharePoint-PnPCalls.Tests.ps1) | Every call in the SharePoint scripts binds against the PnP.PowerShell version the pipeline pins: parameters exist, sit in one parameter set, mandatory ones supplied, `Remove-PnP*` passes `-Force`; and each entry script (publish, bootstrap, build) defines or loads every command it calls. Both PR validation jobs install that version and the suite fails in CI without it; skipped locally without it |
| Blueprint table references | [`Tests/iSOCBlueprint/Get-KqlTableReferences.Tests.ps1`](../../Tests/iSOCBlueprint/Get-KqlTableReferences.Tests.ps1) | The table-to-rule builder over the fixture rules and templates, asserted against the hand-authored reference files (imports `Sentinel.Common`) |
| Blueprint maturity engine | [`Tests/iSOCBlueprint/Get-SentinelMaturity.Tests.ps1`](../../Tests/iSOCBlueprint/Get-SentinelMaturity.Tests.ps1) | Scores the fixture, checks named criteria, roadmap order and the CSF rollup; synthetic criteria for the arithmetic; schema guards on `maturity-criteria.json` |
| Blueprint custom detections | [`Tests/iSOCBlueprint/Get-DefenderCustomDetections.Tests.ps1`](../../Tests/iSOCBlueprint/Get-DefenderCustomDetections.Tests.ps1) | The Graph detectionRule projection against the fixture reference file, plus empty and partial-object cases (dot-sources the module's copy of the Sentinel.Common KQL helpers) |
| Blueprint Word report | [`Tests/iSOCBlueprint/Convert-MarkdownToWord.Tests.ps1`](../../Tests/iSOCBlueprint/Convert-MarkdownToWord.Tests.ps1) | The Word report's Markdown rewrites: status words coloured only under a Severity, Status, Coverage or Rating column, the finding-card severity, and the finding bullets |
| Blueprint connector catalogue | [`Tests/iSOCBlueprint/Get-ConnectorCatalogue.Tests.ps1`](../../Tests/iSOCBlueprint/Get-ConnectorCatalogue.Tests.ps1) | The shipped `connector-catalogue.json` (provenance, unique ids, the core Microsoft connectors) and its helpers: connector ids from classic and codeless connectors, 7-day activity with free tables, connected connectors against the catalogue, the connector and solution labels for a table |
| Blueprint table families | [`Tests/iSOCBlueprint/Get-TableFamily.Tests.ps1`](../../Tests/iSOCBlueprint/Get-TableFamily.Tests.ps1) | `Get-TableFamily` and `Get-ProductFamily`, the source-family mapping shared by the estate flow and the dashboard |
| Blueprint lake tiers | [`Tests/iSOCBlueprint/Get-TableTierProfile.Tests.ps1`](../../Tests/iSOCBlueprint/Get-TableTierProfile.Tests.ps1) | The shared tier classifier behind page 88, the dashboard's lake panel and the billing flow: the four categories, Basic and Auxiliary side counts, extended-retention rows, the not-enrolled case |
| iSOCBlueprint migration map | [`Tests/iSOCBlueprint/Migration-Map.Tests.ps1`](../../Tests/iSOCBlueprint/Migration-Map.Tests.ps1) | The move recorded in [`MIGRATION.md`](../../Modules/iSOCBlueprint/MIGRATION.md) stays complete: `Tools/Blueprint` is gone, no copied, moved or retired source path exists, every destination and vendored original does, copies kept their place in the tree, and every edit a row names is documented |
| iSOCBlueprint vendored copies | [`Tests/iSOCBlueprint/Vendored.Tests.ps1`](../../Tests/iSOCBlueprint/Vendored.Tests.ps1) | The vendor file holds exactly the module's own `Remove-KqlComments` and `Get-KqlBareIdentifiers` (once copies of `Sentinel.Common`'s, which retired in 26.11.0), and the shipped `Blueprint-References.md` equals the docs copy |
| iSOCBlueprint file size | [`Tests/iSOCBlueprint/Structure.Tests.ps1`](../../Tests/iSOCBlueprint/Structure.Tests.ps1) | Every PowerShell file under `Modules/iSOCBlueprint` is within 300 lines; the engine scripts not yet split are listed in the test and the list only shrinks |
| iSOCBlueprint module | [`Tests/iSOCBlueprint/Module.Tests.ps1`](../../Tests/iSOCBlueprint/Module.Tests.ps1) | The manifest (valid, exports one command per `Public/` file, no required modules, version not older than the newest CHANGELOG release), each command's help and file header, the prerequisite list against the engine scripts' `#Requires`, the engine runner (null parameters left out, common parameters passed on, strict mode off), each command's parameter mapping with the engine mocked, `New-iSOCBlueprint`'s step selection and refusals, the collector's alert rules API version and the publisher's default name, and that no Blueprint output is tracked or unignored, with `.githooks/pre-push` run against a throwaway repository |
| iSOCBlueprint standalone | [`Tests/iSOCBlueprint/Module-Standalone.Tests.ps1`](../../Tests/iSOCBlueprint/Module-Standalone.Tests.ps1) | The module copied outside the repository renders the fixture (page 99 from its own copy, GitHub links), builds the SharePoint bundle offline, runs the findings and maturity commands, and loads every engine file it references from inside itself |
| iSOCBlueprint pipelines | [`Tests/iSOCBlueprint/Pipelines.Tests.ps1`](../../Tests/iSOCBlueprint/Pipelines.Tests.ps1) | Every inline script in `Pipelines/Sentinel-Blueprint.yml`, `.github/workflows/sentinel-blueprint.yml` and `.github/workflows/sentinel-sharepoint-publish.yml`, with the pipeline macros stood in for: each iSOCBlueprint call names an exported command, every named parameter and every key of a splatted table binds to it, the module is imported earlier in the same step, no step runs a script from `Tools/Blueprint`, and every repository path the pipelines name (the module, the web part folder, the docs) exists |
| iSOCDeployments module | [`Tests/iSOCDeployments/Module.Tests.ps1`](../../Tests/iSOCDeployments/Module.Tests.ps1) | The manifest (valid, one command per `Public/` file and exactly those exported, no required modules, CalVer not older than the newest CHANGELOG release), each command's help, `iSOC` noun and product name kept out of its name and synopsis, every file's header and `#Requires`, one function per file named after it, ASCII only, and the code rules: no `exit`, no installs, Az cmdlets only in `Private/Az/`, `Invoke-AzRestMethod` only in `Private/Rest/`, Graph SDK commands only in `Private/Graph/`, git only in `Private/Git/`, other web requests only in `Private/Http/`, console output only through `Write-iSOCLog`, no member-name `ForEach-Object` (it returns nothing under `-WhatIf`), no use of `Sentinel.Common` or the iSOC Blueprint; the prerequisite command against the requirement table, its step filter, `-Quiet` and the pinned powershell-yaml version |
| iSOCDeployments core | [`Tests/iSOCDeployments/Core.Tests.ps1`](../../Tests/iSOCDeployments/Core.Tests.ps1) | `Write-iSOCLog` on a console, Azure DevOps and GitHub Actions (each level's logging or workflow command, the GitHub escaping, and every level on every host leaving no pipeline command in the text it writes), the API table and its pinned versions, repository root and relative paths, strict-mode property access, the read-only context and its fallback, request paths per scope, `Connect-iSOCWorkspace` with the Az wrappers and REST mocked (sovereign clouds, subscription switch, missing workspace or playbook group, nothing secret logged) and the requirement checks |
| iSOCDeployments REST client | [`Tests/iSOCDeployments/Rest.Tests.ps1`](../../Tests/iSOCDeployments/Rest.Tests.ps1) | `Invoke-iSOCRestRequest` against a scripted `Invoke-AzRestMethod`: ARM and Graph addressing, the api-version, paging through `nextLink` and `@odata.nextLink`, `-Raw`, bodies, 404 handling, error text without the subscription, retries with and without `Retry-After`, connection failures, writes refused and reads kept under `-WhatIf`; `Get-iSOCRestRetryDelay` and `Get-iSOCRestErrorDetail` |
| iSOCDeployments KQL helpers | [`Tests/iSOCDeployments/Kql.Tests.ps1`](../../Tests/iSOCDeployments/Kql.Tests.ps1) | The comment stripper and the watchlist, `externaldata` and bare-identifier extractors over explicit cases, `Get-iSOCQueryDependency` filing tables, custom log tables, repository parsers and ASIM functions, and `Get-iSOCContentKqlQuery` with `Get-iSOCQueryDependency` over one file of each content shape (a YAML rule, a hunting query, a parser, a JSON summary rule, a Defender detection and files with no readable query), each held to explicit buckets |
| iSOCDeployments YAML helpers | [`Tests/iSOCDeployments/Yaml.Tests.ps1`](../../Tests/iSOCDeployments/Yaml.Tests.ps1) | The scalar writer held to explicit text for awkward values, the subtree writer at each indent, every rule name in the repository reading back as itself, reading with and without key order, empty and unparseable files, and the loader that never installs (MIGRATION.md edit E4) |
| iSOCDeployments comparers | [`Tests/iSOCDeployments/Comparers.Tests.ps1`](../../Tests/iSOCDeployments/Comparers.Tests.ps1) | Every `Compare-iSOCFieldValue` comparer, equal and different, the unset rule, canonical JSON, and durations held to explicit spellings |
| iSOCDeployments content types | [`Tests/iSOCDeployments/ContentTypes.Tests.ps1`](../../Tests/iSOCDeployments/ContentTypes.Tests.ps1) | The registry against the type folders, deploy order, each definition sound with its handlers in its folder, each way `Test-iSOCContentTypeDefinition` catches a wrong definition, the lookups, handler calls and the ordered file walk, including a type with one item |
| iSOCDeployments analytics rules | [`Tests/iSOCDeployments/AnalyticsRule.Tests.ps1`](../../Tests/iSOCDeployments/AnalyticsRule.Tests.ps1) | Reading (identity, the Community source judged from the repository-relative path per MIGRATION.md edit E5, files that do not parse), validation, the request body (core fields, the suppression default, the schedule, the technique split, optional blocks, `-Disabled`, NRT and Community rules) and the query on the fixture repository; the trigger operator, including the values the replaced drift script's `Convert-TriggerOperator` returned; and every rule in `Content/AnalyticalRules/` read, validated and built through the module's handlers (one `It` per file) |
| iSOCDeployments parsers | [`Tests/iSOCDeployments/Parser.Tests.ps1`](../../Tests/iSOCDeployments/Parser.Tests.ps1) | Reading, validation and the saved search body (the file's category kept, blank function parameters left out) on the fixture repository, and every parser in `Content/Parsers/` read, validated and built through the module's handlers (one `It` per file) |
| iSOCDeployments watchlists | [`Tests/iSOCDeployments/Watchlist.Tests.ps1`](../../Tests/iSOCDeployments/Watchlist.Tests.ps1) | One item per folder, the missing-file, field, parse and 3.5 MB checks, the upload with its rows and defaults (MIGRATION.md edit E9) on the fixture repository, and every watchlist in `Content/Watchlists/` read, validated and built through the module's handlers (one `It` per folder) |
| iSOCDeployments hunting queries | [`Tests/iSOCDeployments/HuntingQuery.Tests.ps1`](../../Tests/iSOCDeployments/HuntingQuery.Tests.ps1) | Reading, validation, the saved search body with its tags (and none when the file gives none) and the query on the fixture repository, and every query in `Content/HuntingQueries/` read, validated and built through the module's handlers (one `It` per file) |
| iSOCDeployments playbooks | [`Tests/iSOCDeployments/Playbook.Tests.ps1`](../../Tests/iSOCDeployments/Playbook.Tests.ps1) | Which files are templates, names and identities, validation, the deployment parameters filled in from the workspace, the order (modules after the modules they call, ties in repository order, missing modules and a cycle warned about), the deploy handler (the deployment name cut to 64 characters, validation under `-WhatIf` without one, MIGRATION.md edit E14), the Az.Resources wrappers stood in for, and every template in `Content/Playbooks/` read, validated and given its deployment parameters (one `It` per file), with every module ordered after the modules it calls by a check written apart from the module Also: the fixture repository holds both formats (Bicep read as its compiled template, a Bicep file that does not compile, bicepconfig.json left out, the Bicep CLI needed only for a Bicep file), and `Convert-iSOCPlaybook` (-WhatIf changes nothing, a real run keeps identities and parameters files and has nothing to do again, -Name, and each case that leaves the JSON). |
| iSOCDeployments workbooks | [`Tests/iSOCDeployments/Workbook.Tests.ps1`](../../Tests/iSOCDeployments/Workbook.Tests.ps1) | One item per folder, the missing-template and metadata parse checks, the body from metadata or defaults, the derived workbookId against a value worked out outside PowerShell, ARM-wrapped templates and the file sent as it is, with a warning, when it holds no workbook resource or does not parse, the folder-name split (MIGRATION.md edit E16), and every workbook in `Content/Workbooks/` read, validated and built through the module's handlers (one `It` per folder) |
| iSOCDeployments automation rules | [`Tests/iSOCDeployments/AutomationRule.Tests.ps1`](../../Tests/iSOCDeployments/AutomationRule.Tests.ps1) | Reading, the required-field and parse checks (a missing field reported rather than thrown, MIGRATION.md edit E9), order 0, the body with a single action kept a list, and every rule in `Content/AutomationRules/` read, validated and built through the module's handlers (one `It` per file) |
| iSOCDeployments summary rules | [`Tests/iSOCDeployments/SummaryRule.Tests.ps1`](../../Tests/iSOCDeployments/SummaryRule.Tests.ps1) | Reading, the field, bin size, table and parse checks, the body with and without its optional fields (a bin delay of 0 still sent), and every rule in `Content/SummaryRules/` read, validated and built through the module's handlers (one `It` per file) |
| iSOCDeployments Defender detections | [`Tests/iSOCDeployments/DefenderDetection.Tests.ps1`](../../Tests/iSOCDeployments/DefenderDetection.Tests.ps1) | The Graph contract helpers (the frequency, tactic, entity mapping and automated action converters, the translation of a rule written with the retired fields, the mapped columns); the MITRE ATT&CK 18.1 map; the handlers on the fixture repository: one item per file with the translation done once, validation with every problem on one line and each technique under a tactic it is in (MIGRATION.md E46), and the request body (the current Graph shape, the id first for a create, the defaults, the canonical frequency, an empty action set and null scope, the optional blocks forwarded); `Deploy-iSOCContent -ContentType DefenderDetection` with the REST client mocked: the tenant's rule updated by name in any case, new ones created with their ids, a new one without an id failed, the retired-field warning, the tenant's rules read once and under `-WhatIf` (MIGRATION.md edit E18), a list that cannot be read, a refused body logged, the US Government warning and the powershell-yaml check; and every detection in `Content/DefenderCustomDetections/` read, validated and built for an update and a create (one `It` per file) |
| iSOCDeployments Bicep | [`Tests/iSOCDeployments/Bicep.Tests.ps1`](../../Tests/iSOCDeployments/Bicep.Tests.ps1) | The module's Bicep writer: JSON read with dates kept as text, the ARM expression parser and its canonical text, Bicep strings (every escape, `'''` blocks), identifiers, expressions (parameters, variables, interpolation, symbolic `.id`, operators, function spelling) and a whole template against exact expected text, what the writer refuses, and the template comparison (what counts as the same deployment, how a difference is named); then, through the Bicep CLI, `Invoke-iSOCBicep` building several files in one run and round trips: the fixture playbooks and a template with every awkward value written as Bicep, compiled, and deploying what their JSON deploys |
| iSOCDeployments Content Hub | [`Tests/iSOCDeployments/ContentHub.Tests.ps1`](../../Tests/iSOCDeployments/ContentHub.Tests.ps1) | The version comparison, the customised-rule check (whitespace, duration spelling and severity case ignored, every changed field named in order), the deployment body (compact, nested, non-ASCII escaped) and the 4 MB package limit; the rule template reader, the rule body and the decision for each rule state and switch; `Get-iSOCContentHubSolution` and `Install-iSOCContentHubSolution` against a stand-in Content Hub: each solution's status and action, an outcome and reason for every solution, rule and workbook template, workbook updates and their metadata, the preview alert rules api-version, an NRT rule recreated, rules linked to their solution, templates counted over every page (MIGRATION.md edit E20), the wait only after an install, exclusions, the comma-separated name and a failed run's exit code; then whole runs with every switch, `-DisableRules` alone, `-WhatIf` writing nothing, not even metadata (MIGRATION.md edit E19), and a clean run of one current solution |
| iSOCDeployments workspace deployment | [`Tests/iSOCDeployments/DeployWorkspace.Tests.ps1`](../../Tests/iSOCDeployments/DeployWorkspace.Tests.ps1) | What `Deploy-iSOCWorkspace` gives the workspace settings, Content Hub, custom content and Defender commands for the pipelines' defaults, everything switched and some content left out, held to the explicit values the replaced deploy steps gave the scripts; the stage conditions of `Pipelines/Sentinel-Deploy.yml` and `.github/workflows/sentinel-deploy.yml` read from the YAML and evaluated for every mix of failed and left-out stages, with the command running the stages each pipeline runs; the manifest guard, `-Solution`, `-Stage`, a stage that throws, a failed settings stage holding back nothing, `-WhatIf`, the result and nothing logged that names the subscription (MIGRATION.md edit E44) |
| iSOCDeployments pipeline switch | [`Tests/iSOCDeployments/Pipelines.Tests.ps1`](../../Tests/iSOCDeployments/Pipelines.Tests.ps1) | The module-only Azure DevOps pipelines: `Pipelines/Sentinel-Dependency-Update.yml`, the manifest gate of `Sentinel-PR-Validation.yml`, `Sentinel-Drift-Detect.yml` and `Sentinel-Deploy.yml`. Every pipeline names no removed script and takes no `engine` parameter, the bot branches are read-only, the module steps cannot set variables or change PATH (the deploy check only its two outputs), the commit steps run from main only, stage only their own files and take their runtime variables through env, and the deploy stages run in order (the workspace settings after the infrastructure and before Content Hub, gating nothing; Bicep's `deploySentinel` and playbook group through env). Then each step's inline PowerShell run unchanged in a child pwsh: on a copy of the fixture repository, the update writing a missing or stale manifest and leaving a current one alone, and the gate passing a current manifest and failing a stale or missing one, naming the fix; against stand-ins for the module's commands with the real parameter blocks, what every drift parameter becomes (the defaults, report only, every source left out, failing on drift), the deploy check's two outputs for each onboarding status and the playbook group passed or left empty, what each deploy stage is given with the defaults and every parameter switched, and a failed stage failing the step |
| iSOCDeployments workspace onboarding | [`Tests/iSOCDeployments/WorkspaceOnboarding.Tests.ps1`](../../Tests/iSOCDeployments/WorkspaceOnboarding.Tests.ps1) | The onboarding decision for each state of a workspace; then the Check for Existing Resources step of `.github/workflows/sentinel-deploy.yml`, lifted out of the YAML unchanged and run in a child pwsh with the Az cmdlets stood in for, beside `Get-iSOCWorkspaceOnboarding` over the same stand-in subscription, in eleven states: the same reads in the same order, the same decisions, the GitHub step's errors for the state it cannot repair and nothing logged that names the subscription; then the command's result, the playbook group left out when it is the Sentinel group, a refused read, the api-versions, the subscription switch and the prerequisites (MIGRATION.md edit E42) |
| iSOCDeployments workspace settings | [`Tests/iSOCDeployments/WorkspaceSetting.Tests.ps1`](../../Tests/iSOCDeployments/WorkspaceSetting.Tests.ps1) | Every file under `Content/WorkspaceSettings/`, each way a file can be wrong, the body, the etag (and none for a new setting), a refused setting skipped and any other failure thrown, `-WhatIf`; then the Configure Sentinel Settings step of `.github/workflows/sentinel-deploy.yml` run unchanged in a child pwsh beside `Deploy-iSOCContent -ContentType WorkspaceSetting`, for a new workspace, one with every setting, an identity without the directory role and a setting the service rejects: the same settings, bodies and etags, the same ones deployed, skipped or failed, and the module's api-version; the settings deployed before every other content type (MIGRATION.md edit E43) |
| iSOCDeployments custom tables from a schema | [`Tests/iSOCDeployments/DcrFromSchema.Tests.ps1`](../../Tests/iSOCDeployments/DcrFromSchema.Tests.ps1) | The schema reader (every shipped example and every shape), the repairs, the type, table and column checks, the stream, transform and diff builders, the templates and the deployment error flattener, held to explicit values; thirteen refusals (among them a classic table, a live column type that differs, an Auxiliary table with names differing only by case, a missing resource group, an unrepairable type, retention out of range and a sample of the data rather than a schema), each with its message and nothing written; and `New-iSOCDcrFromSchema` over a stand-in workspace whose tables and rules appear as they are deployed: a run that validates, deploys and grants to a service principal and a user, templates naming the module with LF endings and one final newline, the same file each time, nothing written or deployed under `-WhatIf` and no subscription id logged, the module's commands named in what it says to run, and a relative output folder resolved |
| iSOCDeployments dependency fixture | [`Tests/iSOCDeployments/DependencyFixture.Tests.ps1`](../../Tests/iSOCDeployments/DependencyFixture.Tests.ps1) | The naming plan (every scenario, one alone, no query clamp), ownership of tables, saved searches and rules, the alias guard and the action for each state, and the saved search, rule and record builders, held to explicit values; five refusals (an alias another parser or a workspace table has, a table name other content holds, a workspace without Sentinel, a live query without `-EnableRules`), each with its message and nothing written; and `New-iSOCDependencyFixture` and `Remove-iSOCDependencyFixture` over a stand-in workspace that validates rule queries, refuses to delete classic tables, checks Data Collector signatures and changes as it is written: a full run posting the tables and writing the parsers, hunting query and rules, a removal that migrates and deletes what it owns and skips an unmarked orphan, rule ids derived as the replaced script derived them, and the rules it makes disabled, clamped and naming the module's remove command |
| iSOCDeployments migration rehearsal | [`Tests/iSOCDeployments/Rehearsal.Tests.ps1`](../../Tests/iSOCDeployments/Rehearsal.Tests.ps1) | The Data Collector signature, the fixture and stream records, the token request, the dotenv reader and the DCR readers (target, stream, columns, destination), held to explicit values; then `New-iSOCClassicTableFixture`, `Remove-iSOCClassicTableFixture` and `Test-iSOCDcrIngestion` over a stand-in that checks each Data Collector signature against the workspace key, issues and checks tokens and checks each ingested record against the stream: ingestion granted, tokened and followed, a classic table seeded, five refusals (a wrong secret, a rule with no endpoint, two streams and no choice, an unknown client, no tenant) with nothing ingested, the environment left as it was after reading `.env`, each removal outcome (still classic, removed after migration, not found, `-WhatIf`), and a stream that sends every batch, or ends after `-BatchCount` when every post fails |
| iSOCDeployments classic table migration | [`Tests/iSOCDeployments/ClassicTableMigration.Tests.ps1`](../../Tests/iSOCDeployments/ClassicTableMigration.Tests.ps1) | The stream columns (reserved, hidden and underscore-led columns dropped), the casts in the default transform, the column type map and the template with its keys in a fixed order, held to explicit values over the stand-in schemas; then `Invoke-iSOCClassicTableMigration` over a stand-in workspace whose tables turn DCR-based as they are migrated and whose rules and role assignments appear as they are deployed and granted: listing only (nothing changed, AzureDiagnostics left out, an unreadable table), a transform for more than one table and a text log rule without a file pattern refused, each principal's type passed to the role assignment, a run that migrates, deploys, grants and records a refused deployment, the run's counts and exit code, and the confirmation it asks for without `-Force` |
| iSOCDeployments table migration | [`Tests/iSOCDeployments/TableMigration.Tests.ps1`](../../Tests/iSOCDeployments/TableMigration.Tests.ps1) | Each helper (the KQL readers, alias safety and the reserved names, connector kinds, the playbook and workbook query readers, the JavaScript literal) held to explicit values; the impact analysis over a stand-in workspace (the alias index and the aliases it sets aside, chains, cycles, unresolved bridges, truncation, the fan-out warning, a workspace with no parsers) held to explicit dependents at three depths, and each table's solution matches and connector kinds; `Get-iSOCTableMigrationImpact` and `Export-iSOCTableMigrationReport` over that workspace (the five files, dependents of every kind, the workbook only its own GET returns, GET only at the module's api-versions, one classic table, none, `-WhatIf`, an empty list counted as empty, anything but a review refused); and the module's report template (the module's commands, never `-Force` or `-Confirm:$false`, its version badge, quote escaping, the table name and GUID guards, the copy button, no external resources, chained dependents counted) |
| iSOCDeployments setup | [`Tests/iSOCDeployments/Setup.Tests.ps1`](../../Tests/iSOCDeployments/Setup.Tests.ps1) | The grants and the ABAC condition, the Graph SDK wrappers (a sign-in kept or renewed for its scopes, tenant and cloud, paging), and `Initialize-iSOCServicePrincipal` over a stand-in tenant: the role and directory role assignments held to the explicit values the replaced setup script made, the Graph permission granted after the directory role, held grants left alone, skips, a refused grant failing the run, `-WhatIf` granting nothing and asking before each grant, and a missing service principal (MIGRATION.md edit E34) |
| iSOCDeployments permissions | [`Tests/iSOCDeployments/Permissions.Tests.ps1`](../../Tests/iSOCDeployments/Permissions.Tests.ps1) | The playbook role analysis (each connector's role and scope, the Contributor upgrade, a `/Watchlists` write, a workflow that only reads kept at Responder, HTTP audiences, scopes); role assignments over REST (every page at a scope, one found at or above it, one created under a stable name with the ServicePrincipal type, a 409 as Exists, managed identity principals); then `Grant-iSOCPlaybookPermission`, `Grant-iSOCRunbookPermission` and `Revoke-iSOCRunbookPermission` over a stand-in tenant: the role assignments attempted and the counts held to the explicit values the replaced playbook script gave, each playbook's roles, `-WhatIf`, Key Vault roles skipped without `-KeyVaultName`, the runbook's two roles granted and removed at the scope itself, the confirmation asked and a held assignment left alone, and an Automation Account without an identity (MIGRATION.md edits E32 and E33) |
| iSOCDeployments drift | [`Tests/iSOCDeployments/Drift.Tests.ps1`](../../Tests/iSOCDeployments/Drift.Tests.ps1) | Comparing a rule field by field (whitespace but not case in the query, the case of severity and trigger operator and the spelling of a duration ignored, the schedule for Scheduled rules only, `enabled` and unset fields left out), the YAML rewrite (each field on its line, the query block with its line breaks and a `$` kept, the patch version, CRLF kept), the line diff, slugs, absorbed files (fields, paths, created then unchanged then updated), the classifier for every source and filter; then whole runs of `Compare-iSOCContent`, `Sync-iSOCContent` and `Export-iSOCDriftReport` against a stand-in workspace built from every rule in `Content/AnalyticalRules/`, some edited in the portal, beside Content Hub, orphan, managed and deprecated rules: every bucket filled, edited queries written back, no resource id in the report, report only, left-out sources skipped (MIGRATION.md edits E22 to E24) and a second run finding nothing; `-WhatIf` and no-drift runs writing nothing; a portal rule name holding an Azure DevOps logging command written without it |
| iSOCDeployments export | [`Tests/iSOCDeployments/Export.Tests.ps1`](../../Tests/iSOCDeployments/Export.Tests.ps1) | The workbook helpers (folder names, the workspace suffix, the workspace resource id placeholder, the metadata merge and its key order, MIGRATION.md edit E26) and the playbook helpers (trigger categories, file names, entities, ARM expressions evaluated back to the live values, connections, the template's invariants, the plain-text secret scan); the handlers (the workspace reads, workbooks classified by GUID or as Content Hub, playbooks by PlaybookName or as ambiguous, unreadable and empty items, the files written, a template left alone when only its date would change, MIGRATION.md edit E27); `Export-iSOCContent` (outcomes, a second run, `-Force`, `-Path`, `-WhatIf`, `-IncludeContentHub`, a type it cannot export); and whole runs against a stand-in workspace built from this repository's workbooks: every case counted, curated metadata kept, a workbook written over in its own folder (MIGRATION.md edit E25), a read failure, every page of a list, and playbooks with their secret warnings and `-Force` Also: playbooks written as Bicep by default (`-Format Json` for JSON), the Bicep compiled through the CLI and deploying what the JSON export deploys, a JSON playbook the repository has kept as JSON. |
| iSOCDeployments community import | [`Tests/iSOCDeployments/CommunityImport.Tests.ps1`](../../Tests/iSOCDeployments/CommunityImport.Tests.ps1) | The helpers (the text hash, tags, durations, rule normalisation with the attribution and the API trigger operator, ARM conversion, YAML read in its own key order, version 5 ids, id lines, settling shared and in-house ids, and a re-import of the repository's own Dalonso rules keeping every id); the source definition, the README (MIGRATION.md edit E30), the git requirement and a folder on disk; then `Import-iSOCCommunityRule` cloning a synthetic upstream over file:// into a copy of the repository: every case and outcome counted at the upstream commit, rules written as explicit text with the attribution as its own paragraph, the other rule files left alone, the ids settled, the manifest with each file's hash, the README, a second run writing nothing, `-WhatIf`, a stable id for an ARM rule without a template name and an import from a checkout without cloning (MIGRATION.md edits E28 to E31) |
| iSOCDeployments dependency manifest | [`Tests/iSOCDeployments/Manifest.Tests.ps1`](../../Tests/iSOCDeployments/Manifest.Tests.ps1) | This repository's manifest built byte for byte as the committed `dependencies.json` with no drift, the JSON layout and the comparison held to explicit diff lines, the inventory, entries and missing watchlists on the fixture, and the commands on a copy (writing UTF-8 without a BOM with LF endings, leaving a current file alone, drift and its fix, `-WhatIf`, `-ManifestPath`, the missing-watchlist warning, `Get-iSOCContentDependency` on single files and from the pipeline) |
| iSOCDeployments deploy engine | [`Tests/iSOCDeployments/Deploy.Tests.ps1`](../../Tests/iSOCDeployments/Deploy.Tests.ps1) | The configuration (root and legacy paths), the deployment state (round trip, artifact folder), smart deployment decisions, deploy order, the dependency graph and check, the pre-flight reads (deleted watchlists, unreadable lists, the stale-state reset, MIGRATION.md edit E13), and `Deploy-iSOCContent` over the fixture, all nine types: outcomes, order, api-versions, playbook deployments, the watchlist wait, the state file, `-WhatIf`, type and path selection, the Az.Resources check only when there are playbooks, smart deployment, missing dependencies, the KQL retry, a refused item and config exclusions |
| iSOCDeployments migration map | [`Tests/iSOCDeployments/Migration-Map.Tests.ps1`](../../Tests/iSOCDeployments/Migration-Map.Tests.ps1) | [`MIGRATION.md`](../../Modules/iSOCDeployments/MIGRATION.md) against the repository: each script listed once with a known status, removed scripts gone and the rest present, every function row from a listed script and to a file defining one function named after it (or not ported, with the edit that says why), the old function checked while its source remains, every edit numbered in order, described and named by a row, and a ported unmerged source read from its frozen copy, held to its git blob id; the `Sentinel.Common` mapping check skips now that module is retired |
| iSOCDeployments standalone | [`Tests/iSOCDeployments/Module-Standalone.Tests.ps1`](../../Tests/iSOCDeployments/Module-Standalone.Tests.ps1) | The module copied outside the repository and loaded from the copy without `Sentinel.Common`: it lists its content types, finds a copied fixture repository from a folder inside it and reads, validates and builds every rule, reads a hunting query's dependencies with the parser that repository defines, runs a `-WhatIf` deploy of it, and writes and checks its dependency manifest |

The YAML / JSON schema suites use `-ForEach` to generate one `It` block
per file, so per-file pass/fail surfaces directly in the PR check UI
rather than collapsing into a single combined assertion.

### Wiring the merge gate

The pipelines exit non-zero on test failure, but a non-zero pipeline only
blocks the merge button when explicitly required by branch protection /
build policy. Configure the gate once per platform:

**GitHub** — Repo Settings → Branches → Branch protection rules → Add rule:
- Branch name pattern: `main`
- Require status checks to pass before merging: ON
- Require branches to be up to date before merging: ON
- Required checks (add each as it lands):
  - `validate` (Pester suites)
  - `bicep-build` (Bicep build)
  - `kql-validate` (KQL syntax)
  - `dependency-manifest` (`dependencies.json` drift gate)
  - `arm-validate` (ARM template validation — only after [PR-Validation-Setup.md](../Deploy/PR-Validation-Setup.md) is complete)

**Azure DevOps** — Project Settings → Repos → Repositories → `<repo>` →
Policies → Branch policies for `main`:
- Build validation → + Add build policy
- Build pipeline: `Sentinel-PR-Validation`
- Path filter: `Content/AnalyticalRules/*;Content/HuntingQueries/*;Modules/*;Deploy/*;Tools/*;Tests/*;dependencies.json`
- Trigger: Automatic
- Policy requirement: Required
- Build expiration: Immediately when the source branch is updated
- Display name: `PR Validation`

Once the policy is required, the merge button stays disabled until the
pipeline reports success against the latest commit.

### Community-rule relaxation

One schema rule is intentionally relaxed for files under
`Content/AnalyticalRules/Community/`:

- **GUID-format `id:`** - David Alonso's upstream repo uses
  deliberately-non-GUID identifiers (e.g. `a1b2c3d4-0011-4a5b-8c9d-dns011certutil`).
  We can't change upstream content, and community rules are opt-in
  (`-SkipCommunityDetections` defaults to true) and force-disabled at deploy.

Cross-file `id:` uniqueness is **not** relaxed. The check used to cover
in-house rules only, because the upstream reuses ids across categories, but
the deployer names each rule in the workspace by its id, so two files with
one id are one rule and every deploy overwrites one with the other, disabled
or not. Twelve CommonSecurityLog rules were overwriting twelve SigninLogs
rules that way until they were given ids of their own (release 26.11.0),
and the check now covers the whole tree. See
[Community Rules](../Content/Community-Rules.md#rule-ids).

## Test file layout

Each script test file follows this skeleton (see
[`Tests/Test-PullRequestTemplate.Tests.ps1`](../../Tests/Test-PullRequestTemplate.Tests.ps1)
for a real example; the module suites under `Tests/iSOCDeployments/` import
the module instead):

```powershell
#Requires -Version 7.6
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

<#
.SYNOPSIS
    One sentence: what this suite covers.

.DESCRIPTION
    Which functions are pinned, and what is deliberately not covered
    (anything needing a live workspace usually is not).

.EXAMPLE
    Invoke-Pester -Path Tests/Test-<ScriptName>.Tests.ps1

    Runs the whole suite.

.EXAMPLE
    Invoke-Pester -Path Tests/Test-<ScriptName>.Tests.ps1 -FullName '*FunctionName*'

    Runs one Describe block.

.NOTES
    File:         Tests/Test-<ScriptName>.Tests.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      YYYY-MM-DD
    Version:      0.1.0
    Last Updated: YYYY-MM-DD
    Requires:     PowerShell 7.6+, Pester 5+
#>

BeforeAll {
    # 1. Resolve the source script path, e.g. 'Tools/Test-PullRequestTemplate.ps1'.
    $scriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Tools/<ScriptName>.ps1'

    # 2. AST-extract just the function definitions — see "AST extraction" below
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $scriptPath, [ref]$tokens, [ref]$errors
    )
    $funcs = $ast.FindAll(
        { param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] },
        $false
    )
    $src = ($funcs | ForEach-Object { $_.Extent.Text }) -join "`n`n"

    # 3. Stub any script-scoped constants the functions reference
    $script:Constant1 = 'value'

    # 4. Dot-source the function bodies into the test scope
    . ([ScriptBlock]::Create($src))
}

Describe 'FunctionName' {
    Context 'Some scenario' {
        It 'has the expected behaviour' {
            $result = FunctionName -Input 'x'
            $result | Should -Be 'expected'
        }
    }
}
```

## The AST-extraction pattern

Most production scripts in this repo end with a top-level call like
`Invoke-Main` or have a `param()` block at the top. Naively dot-sourcing
them in a test file would:

- Trigger `Invoke-Main`, which tries to authenticate to Azure
- Choke on mandatory `param(...)` values
- Pollute the test scope with side effects

The AST-extraction pattern walks the parsed script tree, collects only the
top-level `FunctionDefinitionAst` nodes, joins their text, and dot-sources
just that. The param block, the constants, and any final invocation are
left behind.

```powershell
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    $scriptPath, [ref]$tokens, [ref]$errors
)
$funcs = $ast.FindAll(
    { param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] },
    $false   # IMPORTANT: $false = top-level only, not nested helpers
)
. ([ScriptBlock]::Create(($funcs.Extent.Text -join "`n`n")))
```

Critically the `$false` second argument to `FindAll` means "top-level
functions only, not nested ones". Without it you'd duplicate every nested
function definition.

If a function references script-scoped constants (`$script:Foo`), declare
them in `BeforeAll` after the dot-source so the functions can see them:

```powershell
$script:DiffSnippetLength  = 0
$script:SentinelApiVersion = '2025-09-01'
$script:AlertRuleApiVersion = '2025-07-01-preview'
$script:ManagedRuleKinds   = @('Fusion', 'MicrosoftSecurityIncidentCreation')
```

### Module-imports the AST extractor doesn't pull in

The AST extractor pulls *only* function definitions out of the source
script. Top-level statements — `param()`, `#Requires`, `Set-StrictMode`,
and **`Import-Module`** — are deliberately skipped to avoid running the
script's entry-point machinery. Most of the time that's exactly what you
want.

The exception is when an extracted function calls a command from a
module the script imports at top level. Either import that module in the
test's `BeforeAll` after the dot-source, so the extracted functions call
the real implementation, or define a no-op function of the same name to
isolate the test from its output. The deployer scripts that imported
`Sentinel.Common` this way were replaced by the `iSOCDeployments` module
in 26.11.0; its suites under `Tests/iSOCDeployments/` use `Import-Module`
and `InModuleScope` instead of the extractor.

### The Blueprint suites source differently

The Blueprint suites under [`Tests/iSOCBlueprint/`](../../Tests/iSOCBlueprint)
do not go through the AST-extraction helper. They dot-source specific files
of the module's engine directly (including files under
`Modules/iSOCBlueprint/Engine/Private/`) and drive them against a fixed JSON
fixture corpus rather than mocking Azure. The module's own suites
(`Migration-Map`, `Vendored`, `Module`, `Module-Standalone`, `Pipelines`)
are described in the validate table above.

- [`Convert-SentinelInventoryToMarkdown.Tests.ps1`](../../Tests/iSOCBlueprint/Convert-SentinelInventoryToMarkdown.Tests.ps1)
  reshapes `Tests/iSOCBlueprint/Fixtures/sample/_raw` into the `<root>/<workspace>/_raw/*.json`
  layout the renderer [`Modules/iSOCBlueprint/Engine/Convert-SentinelInventoryToMarkdown.ps1`](../../Modules/iSOCBlueprint/Engine/Convert-SentinelInventoryToMarkdown.ps1)
  expects, runs it, and asserts the rendered Markdown (plus an empty-state /
  busy-workspace safety pass).
- [`Get-SentinelGap.Tests.ps1`](../../Tests/iSOCBlueprint/Get-SentinelGap.Tests.ps1)
  dot-sources [`Modules/iSOCBlueprint/Engine/Private/Get-SentinelGap.ps1`](../../Modules/iSOCBlueprint/Engine/Private/Get-SentinelGap.ps1)
  and feeds it a deliberately-broken fixture so each gap-analysis rule fires.
- [`Invoke-SentinelRest.Tests.ps1`](../../Tests/iSOCBlueprint/Invoke-SentinelRest.Tests.ps1)
  dot-sources [`Modules/iSOCBlueprint/Engine/Private/Invoke-SentinelRest.ps1`](../../Modules/iSOCBlueprint/Engine/Private/Invoke-SentinelRest.ps1)
  and asserts URL construction (how `-ApiVersion` is appended when the path
  already carries a query string or its own `api-version`).
- [`Get-KqlTableReferences.Tests.ps1`](../../Tests/iSOCBlueprint/Get-KqlTableReferences.Tests.ps1)
  dot-sources the module's own KQL helpers
  (`Engine/Private/Vendor/SentinelCommon.Kql.ps1`, once a copy of
  `Sentinel.Common`'s, so it needs no Azure modules) and
  [`Modules/iSOCBlueprint/Engine/Private/Get-KqlTableReferences.ps1`](../../Modules/iSOCBlueprint/Engine/Private/Get-KqlTableReferences.ps1).
- [`Get-SentinelMaturity.Tests.ps1`](../../Tests/iSOCBlueprint/Get-SentinelMaturity.Tests.ps1)
  dot-sources the gap engine and
  [`Modules/iSOCBlueprint/Engine/Private/Get-SentinelMaturity.ps1`](../../Modules/iSOCBlueprint/Engine/Private/Get-SentinelMaturity.ps1)
  (which loads the functions under
  [`Modules/iSOCBlueprint/Private/Maturity`](../../Modules/iSOCBlueprint/Private/Maturity)),
  runs both over the fixture, and writes synthetic criteria files to
  `TestDrive:` for the arithmetic cases.
- [`Convert-MarkdownToWord.Tests.ps1`](../../Tests/iSOCBlueprint/Convert-MarkdownToWord.Tests.ps1)
  loads only the functions of
  [`Modules/iSOCBlueprint/Engine/Report/Convert-MarkdownToWord.ps1`](../../Modules/iSOCBlueprint/Engine/Report/Convert-MarkdownToWord.ps1)
  through the PowerShell parser (the script itself runs pandoc) and drives
  them on small Markdown strings; no pandoc, no fixture.
- [`Get-ConnectorCatalogue.Tests.ps1`](../../Tests/iSOCBlueprint/Get-ConnectorCatalogue.Tests.ps1)
  dot-sources
  [`Modules/iSOCBlueprint/Engine/Private/Get-ConnectorCatalogue.ps1`](../../Modules/iSOCBlueprint/Engine/Private/Get-ConnectorCatalogue.ps1),
  checks the shipped catalogue and drives the helpers against a small
  catalogue written to a temporary file; no Azure modules.
- [`Get-TableFamily.Tests.ps1`](../../Tests/iSOCBlueprint/Get-TableFamily.Tests.ps1)
  dot-sources
  [`Modules/iSOCBlueprint/Engine/Private/Get-TableFamily.ps1`](../../Modules/iSOCBlueprint/Engine/Private/Get-TableFamily.ps1)
  and maps table and product names to source families.
- [`Get-TableTierProfile.Tests.ps1`](../../Tests/iSOCBlueprint/Get-TableTierProfile.Tests.ps1)
  dot-sources
  [`Modules/iSOCBlueprint/Engine/Private/Get-TableTierProfile.ps1`](../../Modules/iSOCBlueprint/Engine/Private/Get-TableTierProfile.ps1)
  and classifies a hand-built set of five tables with and without lake
  enrolment; no fixture, no Azure modules.
- [`Section-Model.Tests.ps1`](../../Tests/iSOCBlueprint/Section-Model.Tests.ps1)
  dot-sources the section model helpers under [`Modules/iSOCBlueprint/Engine/Private/`](../../Modules/iSOCBlueprint/Engine/Private),
  converts small inputs directly, then renders the fixture with both output
  formats and with `-OutputFormat Json` and validates every `sections/*.json`
  against [`Modules/iSOCBlueprint/Engine/Schemas/`](../../Modules/iSOCBlueprint/Engine/Schemas).
- [`SharePoint-Site.Tests.ps1`](../../Tests/iSOCBlueprint/SharePoint-Site.Tests.ps1)
  dot-sources the helpers under [`Modules/iSOCBlueprint/Engine/SharePoint/Private/`](../../Modules/iSOCBlueprint/Engine/SharePoint/Private)
  and runs [`Build-SentinelDocsSite.ps1`](../../Modules/iSOCBlueprint/Engine/SharePoint/Build-SentinelDocsSite.ps1)
  (which loads the functions under [`Modules/iSOCBlueprint/Private/Site`](../../Modules/iSOCBlueprint/Private/Site))
  offline against the rendered fixture. The publisher's decisions live in pure
  planning functions, and the functions that call PnP run against stand-in
  functions (`Install-PnPStub`), so nothing needs SharePoint or PnP.PowerShell.
  `Publish-SacSectionPage` runs against a stand-in page object that records
  the web parts it is given.
- [`SharePoint-PnPCalls.Tests.ps1`](../../Tests/iSOCBlueprint/SharePoint-PnPCalls.Tests.ps1)
  parses the SharePoint scripts and checks every PnP.PowerShell call against
  the real parameter metadata of the version `Pipelines/Sentinel-Blueprint.yml`
  pins (`pnpVersion`), so a call that cannot bind fails here instead of in a
  pipeline run. Both PR validation jobs install that version, and in CI the
  suite fails if it is missing. Locally it is skipped without it:
  `Install-Module PnP.PowerShell -RequiredVersion 3.4.1 -Scope CurrentUser`.

Because `Invoke-PRValidation.ps1` sets `Run.Path` to the whole `Tests/`
folder, these run in the PR gate alongside the root suites.

### The cross-reference link checker

The repo's link-checking mechanism lives inside
[`Tests/Test-CopilotCustomisations.Tests.ps1`](../../Tests/Test-CopilotCustomisations.Tests.ps1).
Its "Cross-references resolve" `Describe` block walks the Copilot
customisation files under `.github/` (agents, instructions, prompts,
`copilot-instructions.md`) plus `AGENTS.md`, extracts each relative link, and
asserts the target resolves to a real on-disk path. A renamed or deleted file
that leaves a dangling reference in any of those files fails the `validate`
job.

## Mock builders

For functions that take complex parameter objects, define small builders in
`BeforeAll` that produce baseline values with optional overrides. This
keeps individual `It` blocks short — they only declare the fields the test
actually cares about.

```powershell
function New-DeployedScheduled {
    param([hashtable]$Override = @{})
    $base = @{
        kind             = 'Scheduled'
        displayName      = 'Mock rule'
        severity         = 'Medium'
        # ...full default shape...
    }
    foreach ($k in $Override.Keys) { $base[$k] = $Override[$k] }
    return $base
}
```

Use them like:

```powershell
It 'detects severity change' {
    $deployed = New-DeployedScheduled @{ severity = 'High' }
    $expected = New-DeployedScheduled
    $diff = Compare-SentinelRule -Deployed $deployed -Expected $expected
    $diff.HasDrift | Should -BeTrue
}
```

Each test stays focused on the field it's asserting against.

## `$TestDrive` for file-touching tests

When a function reads or writes files (e.g. `Update-RuleYamlFile`), use
Pester's built-in `$TestDrive` variable as the target directory. Pester
creates a fresh temp folder per test container and removes it automatically
when the run ends.

```powershell
It 'rewrites severity in place' {
    $tmp = Join-Path $TestDrive "rule-$([Guid]::NewGuid()).yaml"
    Copy-Item -Path $script:fixturePath -Destination $tmp

    $mods = @(@{ Field = 'severity'; Deployed = 'High'; Expected = 'Medium' })
    Update-RuleYamlFile -FilePath $tmp -Modifications $mods | Should -BeTrue
    Get-Content -Raw $tmp | Should -Match '(?m)^severity:\s+High\s*$'
}
```

Never write into `$repoRoot/Content/AnalyticalRules/` from a test — that would
mutate real repo files. Always copy the fixture into `$TestDrive` first.

## Adding tests for a new script

1. **Create the test file**: `Tests/<SourceScriptName>.Tests.ps1`. Match
   the source filename so the relationship is unambiguous.

2. **Use the AST-extraction skeleton** above. Replace `<ScriptName>.ps1`
   with the actual source script name and stub any `$script:*` constants
   the functions reference.

3. **Group tests by function**, not by feature: one top-level `Describe`
   block per public function. Inside each, use `Context` blocks to group
   related scenarios (`Context 'Single-field drift'`,
   `Context 'NRT rules'`, `Context 'Empty inputs'`).

4. **Aim for one assertion per `It` block** where practical. Multi-assertion
   `It`s are fine when they're testing the same behaviour from different
   angles, but split them when they're testing distinct contracts.

5. **Run the suite locally** with `-CI` before committing:

   ```powershell
   Invoke-Pester -Path Tests -CI
   ```

## Pester 5 syntax cheat sheet

| Construct | Purpose |
| --- | --- |
| `Describe 'Name' { ... }` | Top-level group, typically per function |
| `Context 'Scenario' { ... }` | Sub-group for related cases within a function |
| `It 'does X' { ... }` | A single test case |
| `BeforeAll { ... }` | Runs once before any tests in the enclosing block |
| `BeforeEach { ... }` | Runs before every `It` in the enclosing block |
| `AfterAll` / `AfterEach` | Cleanup counterparts |
| `Should -Be 'x'` | Strict equality |
| `Should -BeTrue` / `-BeFalse` | Boolean assertions |
| `Should -Match 'regex'` | Regex match |
| `Should -Contain 'x'` | Collection containment |
| `Should -BeNullOrEmpty` | Null or empty string/collection |
| `Should -Throw` | Asserts the script-block throws |
| `$TestDrive` | Per-container temp folder, auto-cleaned |

Full reference: [pester.dev](https://pester.dev/docs/usage/should).

## CI integration (optional)

To gate PRs on the test suite, add a stage to your pipeline:

```yaml
- stage: RunTests
  jobs:
    - job: Pester
      pool:
        vmImage: 'ubuntu-latest'
      steps:
        - checkout: self
        - task: PowerShell@2
          displayName: 'Install Pester'
          inputs:
            targetType: inline
            pwsh: true
            script: Install-Module -Name Pester -Force -SkipPublisherCheck
        - task: PowerShell@2
          displayName: 'Run Pester suite'
          inputs:
            targetType: inline
            pwsh: true
            script: |
              $result = Invoke-Pester -Path Tests -CI -PassThru
              if ($result.FailedCount -gt 0) {
                  Write-Host "##[error]$($result.FailedCount) Pester test(s) failed."
                  exit 1
              }
```

This is a separate concern from the deploy pipeline and the drift pipeline,
so a dedicated `Pipelines/Run-Tests.yml` is the cleanest home for it. Trigger
it on every PR via `pr: { branches: { include: [ main ] } }`.

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `The term 'FunctionName' is not recognized` | AST extraction didn't include the function (e.g. nested in another function, or you passed `$true` to `FindAll` and got duplicates that misbehaved) | Verify with `$ast.FindAll(...).Name -join ','` that the expected function is in the list; ensure the `FindAll` second arg is `$false` |
| `Cannot find path '<TestDrive>'` outside an `It` block | `$TestDrive` is only valid inside test blocks | Move the file write into `It` or `BeforeEach`, not `BeforeAll` at the file scope |
| Tests pass locally but fail in CI | Pester version mismatch — CI on Pester 3.x, local on 5.x (or vice versa) | Pin Pester version in CI: `Install-Module Pester -RequiredVersion 5.7.1 -Force` |
| `Method invocation failed because [Object[]] does not contain a method named 'op_Subtraction'` | PowerShell `$arr[i, j]` indexing is array slicing, not 2-D access | Use jagged arrays (`int[][]`) or `.GetValue(i, j)` instead |
| AST extraction succeeds but functions reference undefined `$script:*` variables | Constants from the source script's prelude weren't stubbed in `BeforeAll` | Declare every `$script:*` the functions need before the dot-source |

## Test inventory

The table lists 32 of the 79 suites: 14 of the 15 root-level
`Tests/*.Tests.ps1` and 18 of the 28 under `Tests/iSOCBlueprint/`. The 36
under `Tests/iSOCDeployments/` are described in the suite table above; the
eleven others added since this table was last brought up to date are not
listed yet. The suites for the scripts the iSOCDeployments module replaced
were removed with them in 26.11.0. Counts are approximate (some suites use `-ForEach`
to generate per-file `It` blocks at discovery time, so the count grows with
the content tree). Run `Invoke-Pester -Path Tests` for a current total.

| File | Coverage | Approx. tests |
| --- | --- | --- |
| [`Tests/Test-AnalyticalRuleYaml.Tests.ps1`](../../Tests/Test-AnalyticalRuleYaml.Tests.ps1) | Per-rule schema (193 analytical + 51 hunting) + cross-file `id` uniqueness | ~24 + per-file |
| [`Tests/Test-AutomationRuleJson.Tests.ps1`](../../Tests/Test-AutomationRuleJson.Tests.ps1) | Action / trigger / propertyValues shape; cross-file id uniqueness | 14 |
| [`Tests/Test-DefenderDetectionYaml.Tests.ps1`](../../Tests/Test-DefenderDetectionYaml.Tests.ps1) | Defender XDR YAML in the current Graph shape: id, retired fields, deployer validation (techniques under their ATT&CK tactics), mapped columns; unique displayName and id | ~167 (per-file) |
| [`Tests/Test-DependencyManifest.Tests.ps1`](../../Tests/Test-DependencyManifest.Tests.ps1) | `dependencies.json` shape + per-entry path / watchlist / function alias resolution | ~1000 (per-entry) |
| [`Tests/Test-ImportScriptFunctions.Tests.ps1`](../../Tests/Test-ImportScriptFunctions.Tests.ps1) | AST extractor synthetic + real-repo round-trip | 6 |
| [`Tests/Test-ParserYaml.Tests.ps1`](../../Tests/Test-ParserYaml.Tests.ps1) | Required fields + KQL identifier validation; functionAlias uniqueness | 4 |
| [`Tests/Test-PlaybookArm.Tests.ps1`](../../Tests/Test-PlaybookArm.Tests.ps1) | Bicep playbooks build clean; ARM template structure + workflow trigger/action presence | 11 (per file) |
| [`Tests/Test-InvokePRValidation.Tests.ps1`](../../Tests/Test-InvokePRValidation.Tests.ps1) | The PR gate's exit code and log for a passing run, a failed test, a suite whose discovery throws, one that does not parse and a failed `AfterAll`, and the report written on failure | 6 |
| [`Tests/Test-PullRequestTemplate.Tests.ps1`](../../Tests/Test-PullRequestTemplate.Tests.ps1) | PR-description parsing + required-section / tick-box validation | 16 |
| [`Tests/Test-SummaryRuleJson.Tests.ps1`](../../Tests/Test-SummaryRuleJson.Tests.ps1) | binSize enum + destinationTable suffix + KQL restriction patterns | 10 |
| [`Tests/Test-WatchlistJson.Tests.ps1`](../../Tests/Test-WatchlistJson.Tests.ps1) | JSON schema + sibling CSV header invariants; alias uniqueness | 9 |
| [`Tests/Test-WorkbookJson.Tests.ps1`](../../Tests/Test-WorkbookJson.Tests.ps1) | ARM-vs-gallery format detection + GUID uniqueness for ARM workbooks | 11 |
| [`Tests/Test-CopilotCustomisations.Tests.ps1`](../../Tests/Test-CopilotCustomisations.Tests.ps1) | Frontmatter parses + required keys present + display-name prefix + applyTo glob hygiene + cross-reference link checker for `.github/agents/`, `.github/instructions/`, `.github/prompts/`, `.github/copilot-instructions.md`, `AGENTS.md` | ~106 (per-file) |
| [`Tests/Test-PowerShellVersion.Tests.ps1`](../../Tests/Test-PowerShellVersion.Tests.ps1) | PowerShell 7.6 everywhere: `#Requires`, `Requires:` and manifest versions, no Windows PowerShell pipeline steps, the Automation runtime environment and the runbook's link to it, no stated requirement below 7.6 | 13 |
| [`Tests/iSOCBlueprint/Convert-SentinelInventoryToMarkdown.Tests.ps1`](../../Tests/iSOCBlueprint/Convert-SentinelInventoryToMarkdown.Tests.ps1) | Blueprint Markdown render from the `Fixtures/sample/_raw` corpus, the merged analytics page, the health-check sections, the orphan-capture tables, the health-check cross-reference sections, the sections added for health-check build 38, full lists with no emoji, the connector catalogue, other saved searches and Sentinel pricing, the pages split out for health-check granularity (02, 16, 21, 22, 89), findings linked to the maturity criteria they decide, and empty-state safety | ~250 |
| [`Tests/iSOCBlueprint/Get-SentinelGap.Tests.ps1`](../../Tests/iSOCBlueprint/Get-SentinelGap.Tests.ps1) | Gap-analysis engine (`Get-SentinelGap`) against a deliberately-broken fixture, per-check outcomes, absent-capture behaviour, the rules ported from health-check build 38, evidence that names every item, SAC-PLT-10 against the connector catalogue | 97 |
| [`Tests/iSOCBlueprint/Invoke-SentinelRest.Tests.ps1`](../../Tests/iSOCBlueprint/Invoke-SentinelRest.Tests.ps1) | `Invoke-SentinelRest` URL construction (api-version / query-string handling) | 5 |
| [`Tests/iSOCBlueprint/Section-Model.Tests.ps1`](../../Tests/iSOCBlueprint/Section-Model.Tests.ps1) | `ConvertTo-BlueprintSection`, `ConvertFrom-BlueprintMermaid`, renderer `sections/*.json` against the schemas | 46 |
| [`Tests/iSOCBlueprint/SharePoint-Site.Tests.ps1`](../../Tests/iSOCBlueprint/SharePoint-Site.Tests.ps1) | `Get-SectionFamily`, `ConvertTo-SharePointPageSegments`, `ConvertTo-SacChartFallbackHtml`, `Get-PageSyncPlan`, `Get-FindingSyncPlan`, `Get-NavigationPlan`, `Add-SacMaturityHistoryEntry`, SharePoint helpers, `Get-SacCatalogApp`, `Publish-SacSectionPage`, `Test-SacPageComponent`, `Wait-SacPageComponent`, `Publish-SacAppPackage`, `Publish-SacDashboardPage`, `Get-SacNavigation`, `Set-SacNavigation`, the web part package (versions, bundles, component ids), offline bundle build (page hashes the same when rebuilt in a fresh process) | 125 |
| [`Tests/iSOCBlueprint/SharePoint-PnPCalls.Tests.ps1`](../../Tests/iSOCBlueprint/SharePoint-PnPCalls.Tests.ps1) | The pinned PnP.PowerShell is installed (fails in CI without it); every PnP.PowerShell call in `Modules/iSOCBlueprint/Engine/SharePoint/` binds against it; each entry script loads every command it calls | 11 |
| [`Tests/iSOCBlueprint/Get-KqlTableReferences.Tests.ps1`](../../Tests/iSOCBlueprint/Get-KqlTableReferences.Tests.ps1) | `Resolve-KqlTableNames`, `Get-RuleTableReferences`, `Get-TemplateTableReferences` against the fixture reference files | 12 |
| [`Tests/iSOCBlueprint/Get-DefenderCustomDetections.Tests.ps1`](../../Tests/iSOCBlueprint/Get-DefenderCustomDetections.Tests.ps1) | `Get-CustomDetectionTableReferences` over the fixture rules and edge cases | 4 |
| [`Tests/iSOCBlueprint/Convert-MarkdownToWord.Tests.ps1`](../../Tests/iSOCBlueprint/Convert-MarkdownToWord.Tests.ps1) | `Convert-StatusWords`, `Convert-FindingBullets` | 7 |
| [`Tests/iSOCBlueprint/Get-ConnectorCatalogue.Tests.ps1`](../../Tests/iSOCBlueprint/Get-ConnectorCatalogue.Tests.ps1) | `connector-catalogue.json` guards, `Import-ConnectorCatalogue`, `Get-WorkspaceConnectorId`, `Get-TableActivity`, `Get-ConnectorCatalogueStatus`, `Get-TableConnectorLabel`, `Get-TableSolutionLabel` | 13 |
| [`Tests/iSOCBlueprint/Get-TableFamily.Tests.ps1`](../../Tests/iSOCBlueprint/Get-TableFamily.Tests.ps1) | `Get-TableFamily`, `Get-ProductFamily` | 20 |
| [`Tests/iSOCBlueprint/Get-TableTierProfile.Tests.ps1`](../../Tests/iSOCBlueprint/Get-TableTierProfile.Tests.ps1) | `Get-TableTier` and `Get-TableTierProfile` over a hand-built table set, enrolled and not | 10 |
| [`Tests/iSOCBlueprint/Get-SentinelMaturity.Tests.ps1`](../../Tests/iSOCBlueprint/Get-SentinelMaturity.Tests.ps1) | `Get-SentinelMaturity` over the fixture, synthetic scoring cases, `maturity-criteria.json` schema guards, `Get-FindingMaturityLink` | 39 |
| [`Tests/iSOCBlueprint/Migration-Map.Tests.ps1`](../../Tests/iSOCBlueprint/Migration-Map.Tests.ps1) | The move out of `Tools/Blueprint` stays complete: every row's source gone and destination present | ~140 (per-row) |
| [`Tests/iSOCBlueprint/Vendored.Tests.ps1`](../../Tests/iSOCBlueprint/Vendored.Tests.ps1) | The vendored KQL helpers and page 99 equal their originals | 4 |
| [`Tests/iSOCBlueprint/Structure.Tests.ps1`](../../Tests/iSOCBlueprint/Structure.Tests.ps1) | Each module file within 300 lines, with a shrinking list of engine scripts not yet split | ~170 |
| [`Tests/iSOCBlueprint/Module.Tests.ps1`](../../Tests/iSOCBlueprint/Module.Tests.ps1) | Manifest, help, file headers, prerequisites, the engine runner, parameter mapping, `New-iSOCBlueprint` step selection, collector and publisher pins, Blueprint output never tracked and the pre-push hook | ~95 |
| [`Tests/iSOCBlueprint/Module-Standalone.Tests.ps1`](../../Tests/iSOCBlueprint/Module-Standalone.Tests.ps1) | The module copied outside the repository renders, builds the site and runs the assessments | 8 |
| [`Tests/iSOCBlueprint/Pipelines.Tests.ps1`](../../Tests/iSOCBlueprint/Pipelines.Tests.ps1) | The Blueprint pipelines' calls to the module bind, after an import; nothing left on `Tools/Blueprint`; every path they name exists | ~55 (per-step and per-path) |

Add new entries to this table as you cover more scripts.

## Authoring with GitHub Copilot

When editing files under `Tests/**`, Copilot automatically loads
[`.github/instructions/pester-tests.instructions.md`](../../.github/instructions/pester-tests.instructions.md).
The path-scoped instructions cover the two test patterns this repo
uses (schema validation `-ForEach` and AST-extraction unit tests),
the mocking conventions (especially `Mock -ModuleName iSOCDeployments`),
and the foot-gun list (single-element array indexing, `$TestDrive`
scoping).

Copilot tooling for tests:

- Slash command `/new-pester-test` (VS Code) — bootstrap a fresh
  test file using the AST-extraction pattern
- Agent `Sentinel-As-Code: Test Engineer` — adds coverage for
  untested scripts, refactors slow / fragile suites, designs
  mocking strategies for tricky dependencies (Az SDK, time-of-day,
  `Invoke-WebRequest` failures)

See [GitHub Copilot setup](../GitHub/GitHub-Copilot.md) for the full layout.

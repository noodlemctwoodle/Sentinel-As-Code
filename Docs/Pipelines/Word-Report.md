# Sentinel Word Report Stage

CI/CD wiring for the `WordReport` stage of
[`Pipelines/Sentinel-Documenter.yml`](../../Pipelines/Sentinel-Documenter.yml),
the Azure DevOps stage that renders the Sentinel Documenter Markdown pack
into a single, styled Word (`.docx`) report and publishes it as a build
artefact.

This page documents the **stage mechanics** (how it is switched on, agent,
steps, outputs, and the GitHub parity story). For what the invoked converter
actually does to the Markdown (pandoc styling, the LibreOffice page-numbered
table of contents, the reference template, and how to run it locally), see the
tool page: [Sentinel Word Report](../Tools/Documenter/Sentinel-Word-Report.md).
This page does not repeat that detail.

## At a glance

| Property | Value |
| --- | --- |
| Pipeline | [`Pipelines/Sentinel-Documenter.yml`](../../Pipelines/Sentinel-Documenter.yml), stage `WordReport` |
| Switched on by | The `publishWordReport` tick box at queue time (default off) |
| Runs after | The `Document` stage, in parallel with the `SharePoint` stage when that is ticked too |
| Input | This run's `sentinel-docs` artefact (`download: current`) |
| Agent pool | `ubuntu-latest` (Microsoft-hosted), its own job |
| Azure auth | **None** (never contacts Azure or Graph) |
| Variable group / secrets | `sentinelWorkspaceName` from `sentinel-deployment` (shared with the rest of the pipeline); `pandocVersion` pipeline variable |
| Published artefact | `sentinel-word-report` (`<workspace>.docx`) |
| GitHub equivalent | **None** (ADO-only, no mirror) |

## Purpose

The [Sentinel Documenter](../Tools/Documenter/Sentinel-Documenter.md) writes a
folder of numbered Markdown section files plus an `assets/` image store to
`SecurityDocs/<workspace>/`. That is good for browsing in a repository but
awkward to hand to a stakeholder. This stage closes the gap: it takes the
Markdown the same run just produced, renders it into one styled,
page-numbered `.docx`, and publishes the document as a build artefact you can
download from the run summary.

The render itself is done by
[`Tools/Documenter/Report/Convert-MarkdownToWord.ps1`](../../Tools/Documenter/Report/Convert-MarkdownToWord.ps1)
in its default `-Toc Baked` mode. See the tool page for how that works.

## Running it

Queue the Documenter (**Pipelines -> Sentinel-Documenter -> Run pipeline**)
and tick **Export: Word report**. Leave **Charts: Mermaid to PNG** on: the
Word report pulls the chart images from `assets/`, and pandoc drops Mermaid
fences, so with pre-rendering off the stage warns and the report carries no
charts. Any mixture of the three outputs (Markdown pull request, Word
report, SharePoint site) can be ticked on the same run.

Download the artefact from the run **Summary -> Published artefacts ->
`sentinel-word-report`**.

## Where the source Markdown comes from

The stage does not generate the Markdown and does not read it from the
repository. It downloads the `sentinel-docs` artefact the `Document` stage
published moments earlier (`download: current`) and renders
`<docsRoot>/<workspace>/`, where `docsRoot` is
`$(Pipeline.Workspace)/sentinel-docs`. The `_raw/` JSON in the artefact is
ignored.

If that folder is missing (the workspace name in the variable group does not
match the run), the convert step logs an error via
`##vso[task.logissue type=error]` and exits non-zero, failing the stage.

## Agent pool

`pool: vmImage: ubuntu-latest` (a Microsoft-hosted Ubuntu agent). Ubuntu is
required because the page-numbered table of contents needs a layout engine,
and LibreOffice plus `python3-uno` install cleanly on the Ubuntu image. See
the tool page for the layout-engine rationale and the local-machine fallback
behaviour.

## Steps, in order

One job, `Render`, with five steps.

### 1. Checkout (`checkout: self`, `fetchDepth: 1`)

Brings the converter scripts and the reference template onto the agent.

### 2. Download the artefact (`download: current`)

Downloads this run's `sentinel-docs` artefact to `$(docsRoot)`.

### 3. Install pandoc + LibreOffice + python3-uno (`script`, bash)

Runs with `set -euo pipefail` and:

- `apt-get install`s `libreoffice-writer`, `python3-uno`, and `fonts-liberation`.
- Downloads the pandoc `.deb` for `$(pandocVersion)` from the pandoc GitHub
  releases and installs it with `dpkg -i`.
- Prints `pandoc --version`, `soffice --version`, and confirms
  `import uno` works (`python3-uno OK`) as a smoke check.

This step needs outbound internet to GitHub and the Ubuntu apt mirrors; it is
the only external network dependency in the stage.

### 4. Convert Markdown to Word (`PowerShell@2`)

- Validates that `<docsRoot>/<workspace>` exists (errors and exits `1` if not).
- Warns when `prerenderChartsToPng` was off for the run.
- Runs
  [`Tools/Documenter/Report/Convert-MarkdownToWord.ps1`](../../Tools/Documenter/Report/Convert-MarkdownToWord.ps1)
  with `-Source`, `-OutputPath $(Build.ArtifactStagingDirectory)/<workspace>.docx`,
  `-Title "<workspace> - Sentinel Documentation"`, and `-Toc Baked`.
- Fails the stage if the script returns non-zero or the `.docx` was not written.
- **TOC verification:** opens the produced `.docx` as a zip, reads
  `word/document.xml`, and counts LibreOffice `__RefHeading` anchors. A baked
  (page-numbered) table of contents carries these anchors, so if the count is
  zero the stage treats the LibreOffice bake as having failed, logs an error,
  and exits `1` rather than publishing a document with an empty contents
  field.

### 5. Publish the artefact (`PublishPipelineArtifact@1`)

Publishes `$(Build.ArtifactStagingDirectory)/<workspace>.docx` as the
pipeline artefact **`sentinel-word-report`**.

## Variables, secrets, and authentication

The stage reads `sentinelWorkspaceName` from the `sentinel-deployment`
variable group (already loaded by the pipeline) and the `pandocVersion`
pipeline variable (`3.10`). It uses **no** service connection, **no** OIDC
or workload identity federation, and **no** API permissions: it only reads
Markdown from the run's artefact and renders it locally on the agent. For
the OIDC setup the other stages use, see
[ADO OIDC Setup](../Deploy/ADO-OIDC-Setup.md).

## Outputs

A single build artefact, **`sentinel-word-report`**, containing the generated
`<workspace>.docx`. Download it from the run **Summary -> Published
artefacts**. Nothing is written back to the repository and no PR is opened
by this stage.

## Failure conditions

The stage fails (non-zero exit, logged via `##vso[task.logissue type=error]`)
if:

- The `Document` stage failed (the stage then does not run at all).
- The install step cannot fetch pandoc or the apt packages.
- `<docsRoot>/<workspace>` is not in the artefact.
- `Convert-MarkdownToWord.ps1` returns non-zero or does not write the `.docx`.
- The baked table of contents is empty (zero `__RefHeading` anchors),
  indicating the LibreOffice bake did not populate the field.

A failed Word report never undoes the `Document` stage: the Markdown artefact
and the docs pull request stand, and "Rerun failed stages" on the run page
renders the same snapshot again.

## GitHub Actions parity

**This stage is ADO-only.** There is no `*word*` workflow under
[`.github/workflows/`](../../.github/workflows) and no GitHub mirror, and the
GitHub Documenter workflow has no equivalent input.

The reasons are practical:

- The page-numbered contents needs LibreOffice plus `python3-uno` on the
  agent, which the Ubuntu ADO image installs cleanly.
- The report is a hand-over document for stakeholders who work from the
  private ADO side, where the Markdown pull request also lands.

The underlying converter is cross-platform and can be run locally on any OS
(with a static-contents fallback when LibreOffice + `python3-uno` are
absent); see the tool page for that. Only the CI wiring is ADO-specific.

## Related

- [Sentinel Word Report (tool / renderer)](../Tools/Documenter/Sentinel-Word-Report.md) - what the converter does, the reference template, and running it locally.
- [Documenter pipeline](Documenter.md) - the pipeline this stage belongs to, with the other two outputs.
- [Sentinel Documenter](../Tools/Documenter/Sentinel-Documenter.md) - the tool that produces the Markdown this stage renders.

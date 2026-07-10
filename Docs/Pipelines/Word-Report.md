# Sentinel Word Report Pipeline

CI/CD wiring for [`Pipelines/Sentinel-Word-Report.yml`](../../Pipelines/Sentinel-Word-Report.yml),
the Azure DevOps pipeline that renders the Sentinel Documenter Markdown pack
into a single, styled Word (`.docx`) report and publishes it as a build
artefact.

This page documents the **pipeline mechanics** (triggers, parameters, agent,
steps, outputs, and the GitHub parity story). For what the invoked converter
actually does to the Markdown (pandoc styling, the LibreOffice page-numbered
table of contents, the reference template, and how to run it locally), see the
tool page: [Sentinel Word Report](../Tools/Documenter/Sentinel-Word-Report.md).
This page does not repeat that detail.

## At a glance

| Property | Value |
| --- | --- |
| File | [`Pipelines/Sentinel-Word-Report.yml`](../../Pipelines/Sentinel-Word-Report.yml) |
| Trigger | Manual only (`trigger: none`, `pr: none`) |
| Agent pool | `ubuntu-latest` (Microsoft-hosted) |
| Azure auth | **None** (never contacts Azure or Graph) |
| Variable group / secrets | **None** |
| Runtime parameters | `sourcePath`, `title`, `outputName`, `pandocVersion` |
| Published artefact | `sentinel-word-report` (the `.docx`) |
| GitHub equivalent | **None** (ADO-only, no mirror) |

## Purpose

The [Sentinel Documenter](../Tools/Documenter/Sentinel-Documenter.md) writes a
folder of numbered Markdown section files plus an `assets/` image store to
`SecurityDocs/<workspace>/`. That is good for browsing in the repo but awkward to
hand to a stakeholder. This pipeline closes the gap: it checks out that committed
folder, renders it into one styled, page-numbered `.docx`, and publishes the
document as a build artefact you can download from the run summary.

The render itself is done by
[`Tools/Documenter/Report/Convert-MarkdownToWord.ps1`](../../Tools/Documenter/Report/Convert-MarkdownToWord.ps1)
in its default `-Toc Baked` mode. See the tool page for how that works.

## Trigger and schedule

The pipeline is **manual-run only**. Both automatic triggers are switched off:

- `trigger: none` disables CI (branch) triggers, so a push never starts it.
- `pr: none` disables pull-request triggers.

There is **no cron schedule** and no `workflow_dispatch` equivalent (that is a
GitHub Actions concept; on ADO the manual queue is the built-in dispatch).
You start a run from **Pipelines -> Sentinel Word Report -> Run pipeline**, set
any parameters that differ from their defaults, then download the artefact from
the build **Summary -> Published artefacts -> `sentinel-word-report`**.

This matches the manual posture of the Documenter pipeline
([`Sentinel-Documenter.yml`](../../Pipelines/Sentinel-Documenter.yml), also
`trigger: none`); the Word Report deliberately runs after you have a fresh
`SecurityDocs/<workspace>/` in the branch.

## Parameters

All four parameters are overridable at queue time:

| Parameter | Type | Default | Description |
| --- | --- | --- | --- |
| `sourcePath` | string | `SecurityDocs/SEC-UKS-PROD-SIEM-WS` | Documenter output folder to render. Must contain the section `.md` files and the `assets/` image folder (the `_raw/` JSON snapshot is ignored). |
| `title` | string | `SEC-UKS-PROD-SIEM-WS - Sentinel Documentation` | The document title passed to the converter. |
| `outputName` | string | `SEC-UKS-PROD-SIEM-WS.docx` | File name for the generated `.docx`, written under the artefact staging directory. |
| `pandocVersion` | string | `3.10` | Pandoc release to install on the agent. Used to build the `.deb` download URL from the pandoc GitHub releases. |

The defaults target the `SEC-UKS-PROD-SIEM-WS` workspace. Point `sourcePath` at a
different `SecurityDocs/<workspace>/` folder to render another workspace's docs,
and set `title` / `outputName` to match.

## Where the source Markdown comes from

The pipeline does not generate the Markdown. It expects
`SecurityDocs/<workspace>/` to already exist in the checked-out branch. That
folder is produced and committed by the Documenter pipeline
([`Sentinel-Documenter.yml`](../../Pipelines/Sentinel-Documenter.yml)) to the
private ADO mirror. This pipeline runs `checkout: self`, which brings that folder
in with the rest of the repo, then renders it.

If `sourcePath` does not resolve, the convert step logs an error via
`##vso[task.logissue type=error]` and exits non-zero, failing the build.

## Agent pool

`pool: vmImage: ubuntu-latest` (a Microsoft-hosted Ubuntu agent). Ubuntu is
required because the page-numbered table of contents needs a layout engine, and
LibreOffice plus `python3-uno` install cleanly on the Ubuntu image. See the tool
page for the layout-engine rationale and the local-machine fallback behaviour.

## Steps, in order

The pipeline is a single implicit job with three steps.

### 1. Checkout (`checkout: self`)

Checks out the repository, which brings `SecurityDocs/<workspace>/` (committed by
the Documenter pipeline) onto the agent.

### 2. Install pandoc + LibreOffice + python3-uno (`script`, bash)

Runs with `set -euo pipefail` and:

- `apt-get install`s `libreoffice-writer`, `python3-uno`, and `fonts-liberation`.
- Downloads the pandoc `.deb` for `${{ parameters.pandocVersion }}` from the
  pandoc GitHub releases (`https://github.com/jgm/pandoc/releases/...`) and
  installs it with `dpkg -i`.
- Prints `pandoc --version`, `soffice --version`, and confirms
  `import uno` works (`python3-uno OK`) as a smoke check.

This step needs outbound internet to GitHub and the Ubuntu apt mirrors; it is the
only external network dependency in the pipeline.

### 3. Convert Markdown to Word (`pwsh`)

- Validates that `sourcePath` exists (errors and exits `1` if not).
- Builds the output path under `$(Build.ArtifactStagingDirectory)` using
  `outputName`.
- Runs
  [`Tools/Documenter/Report/Convert-MarkdownToWord.ps1`](../../Tools/Documenter/Report/Convert-MarkdownToWord.ps1)
  with `-Source`, `-OutputPath`, `-Title`, and `-Toc Baked`.
- Fails the build if the script returns non-zero or the `.docx` was not written.
- **TOC verification:** opens the produced `.docx` as a zip, reads
  `word/document.xml`, and counts LibreOffice `__RefHeading` anchors. A baked
  (page-numbered) table of contents carries these anchors, so if the count is
  zero the pipeline treats the LibreOffice bake as having failed, logs an error,
  and exits `1` rather than publishing a document with an empty contents field.

### 4. Publish the artefact (`publish`)

Publishes `$(Build.ArtifactStagingDirectory)/${{ parameters.outputName }}` as the
pipeline artefact **`sentinel-word-report`**.

## Variable groups, secrets, and repo variables

**None.** The pipeline references no variable group, no secret variables, and no
service-connection-backed variables. Everything it needs is supplied by the four
queue-time parameters and the tools it installs at runtime.

## Authentication

**None.** Unlike [`Sentinel-Deploy.yml`](../../Pipelines/Sentinel-Deploy.yml),
[`Sentinel-Drift-Detect.yml`](../../Pipelines/Sentinel-Drift-Detect.yml), and
the other content pipelines, this pipeline never contacts Azure Resource Manager
or Microsoft Graph. It only reads Markdown that is already committed to the repo
and renders it locally on the agent. Consequently:

- There is **no Azure service connection** (no `sc-sentinel-as-code`).
- There is **no OIDC / workload-identity federation** and no `AzureCLI@2` or
  login task.
- No API permissions or RBAC roles are required to run it.

This is the key CI asymmetry to note: the deploy and drift pipelines authenticate
to Azure via the ADO service connection (or, on GitHub, via the `azure-login-oidc`
composite action's federated credential); the Word Report needs neither because
its input is committed content, not live workspace state. For the OIDC setup those
other pipelines use, see [ADO OIDC Setup](../Deploy/ADO-OIDC-Setup.md).

## Outputs

A single build artefact, **`sentinel-word-report`**, containing the generated
`.docx` (named per the `outputName` parameter). Download it from the build
**Summary -> Published artefacts**. Nothing is written back to the repository and
no PR is opened.

## Failure conditions

The build fails (non-zero exit, logged via `##vso[task.logissue type=error]`) if:

- The install step cannot fetch pandoc or the apt packages.
- `sourcePath` does not resolve on the agent.
- `Convert-MarkdownToWord.ps1` returns non-zero or does not write the `.docx`.
- The baked table of contents is empty (zero `__RefHeading` anchors), indicating
  the LibreOffice bake did not populate the field.

## GitHub Actions parity

**This pipeline is ADO-only.** There is no `*word*` workflow under
[`.github/workflows/`](../../.github/workflows) and no GitHub mirror.

This is one of the two documented asymmetries between the seven ADO pipelines and
the seven GitHub workflows (the other being the GitHub-only
`sentinel-deploy-nightly.yml` E2E smoke test). The reasons the Word Report stays
ADO-only are practical:

- The page-numbered contents needs LibreOffice plus `python3-uno` on the agent,
  which the Ubuntu ADO image installs cleanly.
- The Documenter Markdown it consumes is committed to the private ADO mirror in
  the first place, so the source is already on the ADO side.

The underlying converter is cross-platform and can be run locally on any OS (with
a static-contents fallback when LibreOffice + `python3-uno` are absent); see the
tool page for that. Only the CI wiring is ADO-specific.

## Related

- [Sentinel Word Report (tool / renderer)](../Tools/Documenter/Sentinel-Word-Report.md) - what the converter does, the reference template, and running it locally.
- [Sentinel Documenter](../Tools/Documenter/Sentinel-Documenter.md) - the tool that produces the Markdown this pipeline renders.
- [Pipelines overview](README.md) - the full set of seven ADO pipelines and their GitHub parity table.

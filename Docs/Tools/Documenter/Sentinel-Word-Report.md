# Sentinel Word Report

A pandoc-based toolchain that turns Sentinel Documenter Markdown into a single,
styled Word (`.docx`) report with a real, page-numbered table of contents. The
table of contents is populated by LibreOffice (driven headlessly over the UNO
API), so the document opens fully paginated with no "update fields" prompt.

> Companion page: for the tool that *produces* the Markdown this report renders,
> see [`Sentinel-Documenter.md`](Sentinel-Documenter.md). The Documenter answers
> "what is deployed?" and writes `SecurityDocs/<workspace>/`; the Word Report
> takes that folder and renders it into a shareable `.docx`.

> [!NOTE]
> **This toolchain has an ADO pipeline only.** Unlike the Documenter (which has
> both a GitHub Actions workflow and an Azure DevOps pipeline), the Word Report
> is wired up as `Pipelines/Sentinel-Word-Report.yml` with **no GitHub mirror**.
> The reason is practical: the page-numbered contents needs LibreOffice plus
> `python3-uno` on the agent, which the Ubuntu ADO image installs cleanly, and
> the Documenter Markdown it consumes is committed to the private ADO mirror in
> the first place. You can still run the scripts locally on any platform (see
> [How to run it](#how-to-run-it)).

---

## What it does

The Documenter emits a folder of numbered Markdown section files plus an
`assets/` image store. That is ideal for browsing in a repo but awkward to hand
to a stakeholder who wants one reviewable document. This toolchain closes that
gap:

1. Concatenate the section Markdown in a sensible reading order.
2. Clean it up for print (drop the repeated provenance banner, colour the
   severity labels, split dense finding bullets onto their own lead line).
3. Hand it to **pandoc**, which produces a styled `.docx` (formatted tables,
   embedded images, a genuine Word table-of-contents field) using a bundled
   reference template for the house styles.
4. Ask **LibreOffice** (headless, over UNO) to compute the contents entries and
   page numbers, so the field opens populated rather than blank.

The result is a self-contained Word document: folder-level and section-level
headings in the contents, page numbers that match the body, coloured severity
labels, and the workspace provenance line shown once under the overview.

---

## The pieces

Everything lives under
[`Tools/Documenter/Report/`](../../../Tools/Documenter/Report):

| File | Role |
|---|---|
| [`Convert-MarkdownToWord.ps1`](../../../Tools/Documenter/Report/Convert-MarkdownToWord.ps1) | The main converter. Collects the Documenter `*.md`, cleans and reformats them, runs pandoc, and (by default) bakes the page-numbered TOC. This is what the pipeline runs. |
| [`Update-WordToc.py`](../../../Tools/Documenter/Report/Update-WordToc.py) | The LibreOffice/UNO helper that populates the TOC field's entries and page numbers in place. Called by `Convert-MarkdownToWord.ps1` in its default `Baked` mode. |
| [`Convert-FolderToWordReport.ps1`](../../../Tools/Documenter/Report/Convert-FolderToWordReport.ps1) | A generic, sibling converter that renders *any* folder tree (JSON, CSV, code, logs, Markdown) into a single `.docx`. Handy for turning the Documenter's `_raw/` JSON snapshot into a browsable document. Not used by the pipeline. |
| [`templates/sentinel-report-reference.docx`](../../../Tools/Documenter/Report/templates/sentinel-report-reference.docx) | The pandoc reference document supplying the house styles: grey grid tables with a dark-blue header row and light row banding, heading colours, and the severity/contents character styles. |

The pipeline that stitches these together is
[`Pipelines/Sentinel-Word-Report.yml`](../../../Pipelines/Sentinel-Word-Report.yml).

---

## How the pieces fit

```
SecurityDocs/<workspace>/            (from Sentinel-Documenter.yml, on the ADO mirror)
  ├── <numbered section>.md  ─┐
  ├── ...                     │   Convert-MarkdownToWord.ps1
  ├── index.md   (excluded)   │     - order + clean the Markdown
  ├── README.md  (floated up) │     - pandoc  -> styled .docx + empty TOC field
  └── assets/*.png            │     - Update-WordToc.py (LibreOffice/UNO)
                              │         -> fills TOC entries + page numbers
                              └──> <workspace>.docx   (single, paginated report)
```

`Convert-MarkdownToWord.ps1` does the ordering, cleaning and pandoc call; it then
delegates the pagination to `Update-WordToc.py` through the `Invoke-LibreOfficeBake`
function. Only the `.md` files and their images are used; a sibling `_raw/` folder
of JSON is deliberately ignored, because raw JSON makes a useless code-block dump
rather than a report.

### Why pandoc, not Word COM automation

Both PowerShell scripts are pure PowerShell 7 plus the pandoc binary. There is no
`New-Object -ComObject Word.Application`, so the toolchain runs on macOS, Linux and
Windows alike (the COM route is Windows-only). Neither script imports
`Sentinel.Common` or touches Azure, so they are safe to run anywhere.

### Why LibreOffice for the contents

Pandoc emits a genuine Word TOC *field*, but it cannot lay out pages, so the field
is empty until a layout engine computes page numbers. Running a Basic macro from
the `soffice` command line is documented as unreliable in headless mode (it often
"runs but does nothing"), so `Update-WordToc.py` drives LibreOffice through the UNO
API instead: it starts a private headless listener over a UNO pipe, opens the
document hidden, forces each content index to build from the heading outline
(`CreateFromOutline = True`), updates it, and saves. Its exit codes are `0` success,
`2` bad arguments, `3` the `uno` module is missing, and `4` no connection to
LibreOffice.

---

## Table-of-contents strategies

`Convert-MarkdownToWord.ps1` supports three `-Toc` modes:

| `-Toc` value | Result | External tools |
|---|---|---|
| `Baked` (default) | A real Word TOC field with entries **and page numbers**, populated via LibreOffice so the document opens filled in with no "update fields" prompt. This is what the CI agent uses. | LibreOffice + `python3-uno` |
| `Field` | A real Word TOC field left for Word to populate (open the document and accept the update-fields prompt, or press `Ctrl+A` then `F9`). | None |
| `Styled` | A static, clickable contents link-list styled as a table of contents (indented, no page numbers). Always populated, no prompt. | None |

`Baked` degrades gracefully: if LibreOffice and `python3-uno` are not **both**
available, the script logs a warning and falls back to `Styled` automatically, so
a developer machine without LibreOffice still produces a usable (if page-number-free)
contents. `Get-SofficePath` prefers the macOS app-bundle binary
(`/Applications/LibreOffice.app/Contents/MacOS/soffice`) over any Homebrew `soffice`
wrapper on PATH, because the wrapper launches asynchronously and can return before
the macro finishes.

---

## Prerequisites

**Always required (both scripts):** pandoc on PATH.

```
macOS    brew install pandoc
Windows  winget install --id JohnMacFarlane.Pandoc
Linux    sudo apt-get install pandoc
```

**Required for the `Baked` page-numbered TOC:** LibreOffice plus the Python UNO
bindings.

```
Ubuntu   sudo apt-get install -y libreoffice-writer python3-uno
macOS    brew install --cask libreoffice   (the app bundle carries its own python)
```

Both scripts require **PowerShell 7.2+**. `Update-WordToc.py` requires a `python3`
that carries the `uno` module (`python3 -c 'import uno'` should succeed); on Ubuntu
that is the `python3-uno` package.

---

## Parameters

### `Convert-MarkdownToWord.ps1`

| Parameter | Default | Purpose |
|---|---|---|
| `-Source` (required) | | Folder containing the Markdown, walked recursively. |
| `-OutputPath` | `<Source-leaf>.docx` beside `-Source` | Destination `.docx`. |
| `-Title` | leaf name of `-Source` | Document title, rendered above the contents. |
| `-ReferenceDoc` | bundled `templates/sentinel-report-reference.docx` when present | Pandoc reference doc supplying the house styles. |
| `-NoReferenceDoc` | off | Ignore the bundled template and use pandoc's plain defaults. |
| `-Toc` | `Baked` | Contents strategy: `Baked`, `Field` or `Styled` (see above). |
| `-TocDepth` | `2` | Deepest heading level in the contents (sections and subsections). |
| `-FrontFile` | `README.md` | File names (matched at the source root) floated to the front. |
| `-ExcludeFile` | `index.md` | File names to leave out. The Documenter `index.md` is a link-table duplicate of the real `--toc`, so it is dropped to avoid a second contents table. |
| `-StripLinePattern` | provenance blockquote regex | Multiline regex for lines to delete before conversion. Defaults to the repeated Documenter provenance banner (`> **Workspace** ... **Documenter** vX`), which is kept once in the first section and stripped from the rest. Pass `''` to keep everything. |
| `-NoReformatFindings` | off | Leave the dense finding bullets and severity labels untouched. |

Two pandoc behaviours are always applied, learned against real Documenter output:

- **`-f gfm`** (GitHub-Flavored Markdown, extended with `fenced_divs`,
  `bracketed_spans` and `raw_attribute`). The default `markdown` reader treats a
  `---` after a blank line as a YAML metadata block; the Documenter uses `---` as
  a horizontal rule, which trips a YAML parse exception. GFM has no YAML-metadata
  concept, so `---` stays a rule.
- **`--resource-path`** set to every directory under `-Source`, so relative image
  links such as `assets/X.png` resolve wherever the asset store sits. Otherwise
  pandoc resolves them against the working directory and silently drops them.

When `-NoReformatFindings` is *not* set, the script also rewrites the report for
print: `Convert-FindingBullets` turns dense finding bullets shaped like
`- **<severity>** [<ID>](<link>) <title> - <description>` into a bold
severity/ID/title lead line with the description beneath (resolving the title from
the matching gap-analysis heading), and `Convert-SeverityEmoji` replaces status
emoji such as `🟠 Warning` with the word alone, coloured via a character style. The
colours come from the `SevCritical`, `SevWarning`, `SevLow` and `SevInfo` character
styles defined in the reference template; the static contents uses `TOCEntry1`
through `TOCEntry3`.

### `Convert-FolderToWordReport.ps1`

The generic converter renders an arbitrary folder tree, grouping files by their
top-level subfolder (a level-1 heading) with each file under its own level-2
heading, so the contents reads folder then file.

| Parameter | Default | Purpose |
|---|---|---|
| `-Source` (required) | | Folder whose contents become the report, walked recursively. |
| `-OutputPath` | `<Source-leaf>.docx` beside `-Source` | Destination `.docx`. |
| `-Title` | leaf name of `-Source` | Document title. |
| `-ReferenceDoc` | none | Optional pandoc reference `.docx` (no bundled default here). |
| `-MaxFileKB` | `1024` | Per-file size ceiling in KB; larger files are truncated with a note. `0` disables truncation. |
| `-TableRowLimit` | `200` | CSV/TSV files with at most this many data rows render as a Markdown table; larger ones fall back to a code block. |
| `-KeepMarkdown` | off | Keep the intermediate Markdown (beside `-OutputPath` with a `.md` extension) for debugging. |

It renders each file by type: `.json` pretty-printed in a fenced block, `.csv`/`.tsv`
as a Markdown table or code block, code and log files (`.kql`, `.yaml`, `.ps1`,
`.xml`, `.bicep`, `.sql`, `.log`, `.txt` and similar) fenced with a language hint,
`.md` inlined as-is, and binary or unreadable files noted and skipped with their
size. Code fences use tildes rather than backticks, because file content very
commonly contains backticks but almost never tildes. This converter uses pandoc's
plain `--toc` field (like `-Toc Field` above); it does not bake page numbers.

---

## How to run it

### Locally

Render the Documenter Markdown for one workspace into a paginated report:

```powershell
./Tools/Documenter/Report/Convert-MarkdownToWord.ps1 `
    -Source     '/private/tmp/SEC-UKS-PROD-SIEM-WS' `
    -OutputPath "$HOME/Desktop/SEC-UKS-PROD-SIEM-WS.docx" `
    -Title      'SEC-UKS-PROD-SIEM-WS - Sentinel Documentation'
```

With pandoc, LibreOffice and `python3-uno` all present this produces a baked,
page-numbered contents. On a machine missing LibreOffice or the UNO bindings it
falls back to a static `Styled` contents automatically. To force a no-LibreOffice
run, pass `-Toc Styled` (static list) or `-Toc Field` (Word populates on open).

To turn the Documenter's raw JSON snapshot into a browsable document instead:

```powershell
./Tools/Documenter/Report/Convert-FolderToWordReport.ps1 `
    -Source '/private/tmp/SEC-UKS-PROD-SIEM-WS/_raw'
```

### Azure DevOps pipeline

[`Pipelines/Sentinel-Word-Report.yml`](../../../Pipelines/Sentinel-Word-Report.yml)
is **manual-only** (`trigger: none`, `pr: none`) and runs on `ubuntu-latest`. To run
it: **Pipelines -> Sentinel Word Report -> Run pipeline**, adjust the parameters if
they differ from the defaults, then download the artefact from **Build summary ->
Published artefacts -> `sentinel-word-report`**.

| Parameter | Default | Purpose |
|---|---|---|
| `sourcePath` | `SecurityDocs/SEC-UKS-PROD-SIEM-WS` | The Documenter output folder to render (must contain the section `.md` files and the `assets/` image folder; `_raw/` is ignored). |
| `title` | `SEC-UKS-PROD-SIEM-WS - Sentinel Documentation` | Document title. |
| `outputName` | `SEC-UKS-PROD-SIEM-WS.docx` | Output `.docx` file name. |
| `pandocVersion` | `3.10` | Pandoc release to install on the agent. |

The pipeline installs `libreoffice-writer`, `python3-uno`, `fonts-liberation` and
the requested pandoc `.deb`, runs `Convert-MarkdownToWord.ps1 -Toc Baked`, and then
**verifies the bake actually happened**: it opens the produced `.docx`, reads
`word/document.xml`, and counts LibreOffice's `__RefHeading` anchors. If the count is
zero the TOC field came out empty, so the build fails rather than publishing a broken
document. On success it publishes the `.docx` as the artefact `sentinel-word-report`.

The Markdown this pipeline consumes is produced upstream by
[`Sentinel-Documenter.yml`](../../../Pipelines/Sentinel-Documenter.yml), which
commits `SecurityDocs/<workspace>/` to the private ADO mirror; this pipeline checks
that out and converts it. Because the Documenter output carries detailed tenant
configuration, keep the ADO project private and treat the resulting `.docx` as
sensitive.

---

## What this toolchain is not

- **Not a data collector.** It only renders Markdown that already exists. The
  collection and gap analysis are the Documenter's job.
- **Not a Word installation.** It never touches Word or COM; pandoc and LibreOffice
  do all the work, so it runs headless on any platform.
- **Not tied to Sentinel.** Both scripts are content-agnostic and import nothing
  from `Sentinel.Common`. `Convert-FolderToWordReport.ps1` in particular is a
  general folder-to-Word converter.

---

## Related

- [`Sentinel-Documenter.md`](Sentinel-Documenter.md): the tool that produces the
  Markdown and `assets/` this report renders.
- [`Documenter-Renderer-Design.md`](Documenter-Renderer-Design.md): how the
  Documenter Markdown and charts are generated in the first place.
- [`Documenter-References.md`](Documenter-References.md): durable reference of API
  versions, modules and Microsoft Learn pages used across the Documenter.

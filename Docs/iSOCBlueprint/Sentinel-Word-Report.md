# Sentinel Word Report

A pandoc-based toolchain that turns Sentinel Blueprint Markdown into a single,
styled Word (`.docx`) report with a real, page-numbered table of contents. The
table of contents is populated by LibreOffice (driven headlessly over the UNO
API), so the document opens fully paginated with no "update fields" prompt.

> Companion page: for the tool that *produces* the Markdown this report renders,
> see [`Sentinel-Blueprint.md`](Sentinel-Blueprint.md). The Blueprint answers
> "what is deployed?" and writes `SecurityDocs/<workspace>/`; the Word Report
> takes that folder and renders it into a shareable `.docx`.

> [!NOTE]
> **This toolchain runs on ADO only.** The Word report is the `WordReport`
> stage of `Pipelines/Sentinel-Blueprint.yml`, switched on by the
> `publishWordReport` tick box at queue time, with **no GitHub mirror**.
> The reason is practical: the page-numbered contents needs LibreOffice plus
> `python3-uno` on the agent, which the Ubuntu ADO image installs cleanly, and
> the Blueprint Markdown it consumes is committed to the private ADO mirror in
> the first place. You can still run it locally on any platform with the
> module's `Export-iSOCBlueprintWord` (see [How to run it](#how-to-run-it)).

---

## What it does

The Blueprint emits a folder of numbered Markdown section files plus an
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

The command is [`Export-iSOCBlueprintWord`](../../Modules/iSOCBlueprint/Public/Export-iSOCBlueprintWord.ps1)
from the iSOCBlueprint module. What it runs lives under
[`Modules/iSOCBlueprint/Engine/Report/`](../../Modules/iSOCBlueprint/Engine/Report):

| File | Role |
|---|---|
| [`Convert-MarkdownToWord.ps1`](../../Modules/iSOCBlueprint/Engine/Report/Convert-MarkdownToWord.ps1) | The main converter. Collects the Blueprint `*.md`, cleans and reformats them, runs pandoc, and (by default) bakes the page-numbered TOC. `Export-iSOCBlueprintWord` runs it, locally and in the pipeline. |
| [`Update-WordToc.py`](../../Modules/iSOCBlueprint/Engine/Report/Update-WordToc.py) | The LibreOffice/UNO helper that populates the TOC field's entries and page numbers in place. Called by `Convert-MarkdownToWord.ps1` in its default `Baked` mode. |
| [`templates/sentinel-report-reference.docx`](../../Modules/iSOCBlueprint/Engine/Report/templates/sentinel-report-reference.docx) | The pandoc reference document supplying the house styles: grey grid tables with a dark-blue header row and light row banding, heading colours, and the severity/contents character styles. |

The stage that stitches these together lives in
[`Pipelines/Sentinel-Blueprint.yml`](../../Pipelines/Sentinel-Blueprint.yml).

---

## How the pieces fit

```
SecurityDocs/<workspace>/            (from Sentinel-Blueprint.yml, on the ADO mirror)
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

The converter is pure PowerShell 7 plus the pandoc binary. There is no
`New-Object -ComObject Word.Application`, so the toolchain runs on macOS, Linux and
Windows alike (the COM route is Windows-only). It does not touch Azure, so it is
safe to run anywhere.

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

`Export-iSOCBlueprintWord` (through `Convert-MarkdownToWord.ps1`) supports three `-Toc` modes:

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

**Always required:** pandoc on PATH.

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

The module requires **PowerShell 7.2+**. `Update-WordToc.py` requires a `python3`
that carries the `uno` module (`python3 -c 'import uno'` should succeed); on Ubuntu
that is the `python3-uno` package. `Test-iSOCBlueprintPrerequisite -Step Word`
reports which of these a machine has.

---

## Parameters

### `Export-iSOCBlueprintWord`

| Parameter | Default | Purpose |
|---|---|---|
| `-Path` (required; alias `-Source`) | | Folder containing the Markdown, walked recursively. Takes the `Path` of `ConvertTo-iSOCBlueprint`'s output from the pipeline. |
| `-OutputPath` | `<Path-leaf>.docx` beside `-Path` | Destination `.docx`. |
| `-Title` | leaf name of `-Path` | Document title, rendered above the contents. |
| `-ReferenceDoc` | bundled `templates/sentinel-report-reference.docx` when present | Pandoc reference doc supplying the house styles. |
| `-NoReferenceDoc` | off | Ignore the bundled template and use pandoc's plain defaults. |
| `-Toc` | `Baked` | Contents strategy: `Baked`, `Field` or `Styled` (see above). |
| `-TocDepth` | `2` | Deepest heading level in the contents (sections and subsections). |
| `-FrontFile` | `README.md` | File names (matched at the source root) floated to the front. |
| `-ExcludeFile` | `index.md` | File names to leave out. The Blueprint `index.md` is a link-table duplicate of the real `--toc`, so it is dropped to avoid a second contents table. |
| `-StripLinePattern` | provenance blockquote regex | Multiline regex for lines to delete before conversion. Defaults to the repeated Blueprint provenance banner (`> **Workspace** ... **Blueprint** vX`), which is kept once in the first section and stripped from the rest. Pass `''` to keep everything. |
| `-NoReformatFindings` | off | Leave the dense finding bullets and severity labels untouched. |

Two pandoc behaviours are always applied, learned against real Blueprint output:

- **`-f gfm`** (GitHub-Flavored Markdown, extended with `fenced_divs`,
  `bracketed_spans` and `raw_attribute`). The default `markdown` reader treats a
  `---` after a blank line as a YAML metadata block; the Blueprint uses `---` as
  a horizontal rule, which trips a YAML parse exception. GFM has no YAML-metadata
  concept, so `---` stays a rule.
- **`--resource-path`** set to every directory under `-Source`, so relative image
  links such as `assets/X.png` resolve wherever the asset store sits. Otherwise
  pandoc resolves them against the working directory and silently drops them.

When `-NoReformatFindings` is *not* set, the script also rewrites the report for
print: `Convert-FindingBullets` turns dense finding bullets shaped like
`- **<severity>** [<ID>](<link>) <title> - <description>` into a bold
severity/ID/title lead line with the description beneath (resolving the title from
the matching gap-analysis heading), and `Convert-StatusWords` colours the status
words through a character style: a table cell under a Severity, Status, Coverage
or Rating column whose whole text is a known status (`Warning`, `Gap`, `None`,
`Strong`), and the value after `**Severity:**` on the finding cards. A word in any
other column stays plain. The
colours come from the `SevCritical`, `SevWarning`, `SevLow` and `SevInfo` character
styles defined in the reference template; the static contents uses `TOCEntry1`
through `TOCEntry3`.

---

## How to run it

### Locally

Render the Blueprint Markdown for one workspace into a paginated report:

```powershell
Import-Module ./Modules/iSOCBlueprint

# Charts are Mermaid fences until they are images, and pandoc drops fences:
# draw them first (needs mmdc), then convert.
ConvertTo-iSOCBlueprintChartImage -Path ./SecurityDocs
Export-iSOCBlueprintWord `
    -Path       ./SecurityDocs/law-sentinel-prod `
    -OutputPath ./law-sentinel-prod.docx `
    -Title      'law-sentinel-prod - Sentinel Documentation'
```

Or collect, render, draw the charts and convert in one line with
`New-iSOCBlueprint -ResourceGroup <rg> -WorkspaceName <ws> -Format Word -ChartImages`.

With pandoc, LibreOffice and `python3-uno` all present this produces a baked,
page-numbered contents. On a machine missing LibreOffice or the UNO bindings it
falls back to a static `Styled` contents automatically. To force a no-LibreOffice
run, pass `-Toc Styled` (static list) or `-Toc Field` (Word populates on open).

### Azure DevOps pipeline

The `WordReport` stage of
[`Pipelines/Sentinel-Blueprint.yml`](../../Pipelines/Sentinel-Blueprint.yml)
runs on `ubuntu-latest` after the `Document` stage and renders that run's
artefact. To run it: **Pipelines -> Sentinel-Blueprint -> Run pipeline**,
tick **Export: Word report** (and leave **Charts** on), then download
the artefact from **Build summary -> Published artefacts ->
`sentinel-word-report`**. See [Word-Report.md](../Pipelines/Word-Report.md).

The stage takes no inputs of its own: it renders `<workspace>` from the run's
`sentinel-docs` artefact with the title `<workspace> - Sentinel Documentation`
into `<workspace>.docx`. The pipeline variable `pandocVersion` (`3.10`) picks the
pandoc release installed on the agent.

The pipeline installs `libreoffice-writer`, `python3-uno`, `fonts-liberation` and
the requested pandoc `.deb`, runs `Export-iSOCBlueprintWord -Toc Baked`, and then
**verifies the bake actually happened**: it opens the produced `.docx`, reads
`word/document.xml`, and counts LibreOffice's `__RefHeading` anchors. If the count is
zero the TOC field came out empty, so the build fails rather than publishing a broken
document. On success it publishes the `.docx` as the artefact `sentinel-word-report`.

The Markdown this stage consumes is the `Document` stage's output from the same
run of [`Sentinel-Blueprint.yml`](../../Pipelines/Sentinel-Blueprint.yml), read
from the `sentinel-docs` artefact. Because the Blueprint output carries detailed
tenant configuration, keep the ADO project private and treat the resulting
`.docx` as sensitive.

---

## What this toolchain is not

- **Not a data collector.** It only renders Markdown that already exists. The
  collection and gap analysis are the Blueprint's job.
- **Not a Word installation.** It never touches Word or COM; pandoc and LibreOffice
  do all the work, so it runs headless on any platform.
- **Not tied to Sentinel.** The converter is content-agnostic: it renders
  whatever Markdown pack it is given.

---

## Related

- [`Sentinel-Blueprint.md`](Sentinel-Blueprint.md): the tool that produces the
  Markdown and `assets/` this report renders.
- [`Blueprint-Renderer-Design.md`](Blueprint-Renderer-Design.md): how the
  Blueprint Markdown and charts are generated in the first place.
- [`Blueprint-References.md`](Blueprint-References.md): durable reference of API
  versions, modules and Microsoft Learn pages used across the Blueprint.

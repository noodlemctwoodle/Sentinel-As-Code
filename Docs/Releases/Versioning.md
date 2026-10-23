# Versioning

Sentinel-As-Code uses two independent version schemes:

- The **repository / release** uses **CalVer** (date-based).
- The **`Sentinel.Common` PowerShell module** uses **SemVer** (it is a
  Gallery-style reusable library, versioned independently).

A repository release may ship with an unchanged module version, and vice versa.

## Repository CalVer

Format: **`YY.0M`** - two-digit year, zero-padded month.

| Example | Meaning |
|---------|---------|
| `26.06` | June 2026 |
| `26.11` | November 2026 |
| `27.01` | January 2027 |

This sorts correctly both lexically and chronologically (lexical order ==
release order), which keeps release branches and release lists ordered.

### Same-month releases

When more than one release ships in the same calendar month, append a
Black-style micro ordinal starting at `0`:

| Version | |
|---------|---|
| `26.06.0` | first June 2026 release |
| `26.06.1` | second June 2026 release |

A month's sole release is written bare (`26.05`); a month with two or more
releases uses the micro suffix.

### Release branches, GitHub Releases and tags

The release mechanism is:

1. A `release/<CalVer>` branch is cut for the release (for example
   `release/26.10.0`), following the same `YY.0M[.micro]` string as the
   version itself. Work lands on the release branch via PR before it merges
   to `main`.
2. Once merged, the release is published as a **GitHub Release** named after
   the CalVer string (for example `26.10.0`), with the release notes drawn
   from `Docs/Releases/` / the CHANGELOG.
3. The GitHub Release tags the release PR's merge commit on `main` with `v`
   followed by the CalVer string (for example `v26.10.0`). GitHub creates the
   tag when the release is published, so there is no separate `git tag` step.

`26.10.0` is the first release published this way: `v26.10.0` is the
repository's first tag and its first GitHub Release. Earlier releases have
neither; their code is the merge of their release PR into `main` (the PRs
are listed in the history below).

## Wave → CalVer history

"Wave N" was the pre-CalVer release label (now retired; it survives only in
immutable git history). The mapping:

| Former label | CalVer | Notes |
|--------------|--------|-------|
| Wave 1 | `26.03` | approximate (pre-CalVer history) |
| Wave 2 | `26.04` | approximate (direct-to-main batch) |
| Wave 3 | `26.05` | PR #7 |
| Wave 4 | `26.06.0` | PR #25 |
| Repository restructure | `26.06.1` | PR #27 |
| Word report + Apache-2.0 relicence | `26.07` | PR #29 |
| Copilot activity monitoring content pack, Sentinel as Code Toolkit, PR template validation gate | `26.07.1` | PR #30, PR #31 |
| Documentation overhaul, Toolkit and pipeline docs, Docs restructure, deploy fixes | `26.07.2` | PR #33 |
| Classic-to-DCR and DCR-from-schema toolkits, Spark notebooks, MCP prompt books, drift-sync fix, docs housekeeping | `26.07.3` | PR #34, PR #35, PR #37, PR #40, PR #42, PR #43, PR #44, PR #45, PR #46, PR #47 |
| Sophos codeless connector, Detection Engineering dashboard, connector-metadata corrections, PowerShell header standardisation | `26.09` | PR #49, PR #50, PR #52, PR #53, PR #54, PR #55, PR #57 |
| The iSOCBlueprint module (its first release), the iSOC Blueprint SharePoint site and dashboard, the Sentinel health check folded in, a failed sign-in burst rule, nightly failure issues closing on recovery, Toolkit docs, drift-sync manifest fix | `26.10.0` | PR #59, PR #60, PR #61, PR #64, PR #65 |

Each release shipped as a `release/<CalVer>` branch merged to `main`. Up to
`26.09` there was no tag and no GitHub Release; `26.10.0` is the first with
both (`v26.10.0`). The `26.07.1` row's PR template validation gate is the
`template` check: it fails a pull request whose description leaves a
required section of `.github/PULL_REQUEST_TEMPLATE.md` empty (Summary, Why
is this change needed?, What does this change do?, Testing) or ticks no
"Type of change" box.

## Module SemVer

`Modules/Sentinel.Common` follows SemVer in its `.psd1` `ModuleVersion` /
`ReleaseNotes` (currently `1.1.1`). Bump it per the usual major / minor / patch
rules when the module's API or behaviour changes, independently of the
repository CalVer release it happens to ship with.

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

### Release branches and GitHub Releases

The repository does **not** use git tags for releases (`git tag --list`
returns zero results, and none have ever been created). The release
mechanism is:

1. A `release/<CalVer>` branch is cut for the release (for example
   `release/26.07.1`), following the same `YY.0M[.micro]` string as the
   version itself. Work lands on the release branch via PR before it merges
   to `main`.
2. Once merged, the release is published as a **GitHub Release** named after
   the CalVer string (for example `26.07.1`), with the release notes drawn
   from `Docs/Releases/` / the CHANGELOG.

If tagging is introduced in future, it should tag the merge commit of the
release PR with `v` + the CalVer string (e.g. `v26.07.1`) so the convention
matches the release branch and GitHub Release naming - but this is not
current practice and no such tags exist today.

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

None of these releases were git-tagged; each shipped as a `release/<CalVer>`
branch merged to `main` and, where published, a GitHub Release. The
"Copilot content pack, authoring toolkit, PR-template scaffolding" row adds
`.github/agents/`, `.github/prompts/`, `.github/instructions/`, and
`.github/PULL_REQUEST_TEMPLATE.md`; the template's sections are informational
only (its own text notes "Empty sections / unchecked boxes are fine") and
are not enforced by any CI gate today.

## Module SemVer

`Modules/Sentinel.Common` follows SemVer in its `.psd1` `ModuleVersion` /
`ReleaseNotes` (currently `1.1.1`). Bump it per the usual major / minor / patch
rules when the module's API or behaviour changes, independently of the
repository CalVer release it happens to ship with.

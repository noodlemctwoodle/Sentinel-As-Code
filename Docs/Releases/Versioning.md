# Versioning

Sentinel-As-Code uses two independent version schemes:

- The **repository / release** uses **CalVer** (date-based).
- The **`Sentinel.Common` PowerShell module** uses **SemVer** (it is a
  Gallery-style reusable library, versioned independently).

A repository release may ship with an unchanged module version, and vice versa.

## Repository CalVer

Format: **`YY.0M`** — two-digit year, zero-padded month.

| Example | Meaning |
|---------|---------|
| `26.06` | June 2026 |
| `26.11` | November 2026 |
| `27.01` | January 2027 |

This sorts correctly both lexically and chronologically (lexical order ==
release order), which keeps git tags and release lists ordered.

### Same-month releases

When more than one release ships in the same calendar month, append a
Black-style micro ordinal starting at `0`:

| Version | |
|---------|---|
| `26.06.0` | first June 2026 release |
| `26.06.1` | second June 2026 release |

A month's sole release is written bare (`26.05`); a month with two or more
releases uses the micro suffix.

### Tagging

Tag the merge commit of the release PR with `v` + the CalVer string:

```bash
git tag -a v26.06.1 -m "Sentinel-As-Code 26.06.1"
git push origin v26.06.1
```

Tags are annotated; releases mirror to GitHub Releases.

## Wave → CalVer history

"Wave N" was the pre-CalVer release label (now retired; it survives only in
immutable git history). The mapping:

| Former label | CalVer | Notes |
|--------------|--------|-------|
| Wave 1 | `26.03` | approximate (pre-tag history) |
| Wave 2 | `26.04` | approximate (direct-to-main batch) |
| Wave 3 | `26.05` | PR #7 |
| Wave 4 | `26.06.0` | PR #25 |
| Repository restructure | `26.06.1` | first tagged release |
| Word report + Apache-2.0 relicence | `26.07` | PR #29 |
| Copilot content pack, authoring toolkit, PR-template gate | `26.07.1` | PRs #30, #31 |

Tagging begins at `v26.06.1`; earlier releases are recorded here for reference
and are not retroactively tagged.

## Module SemVer

`Modules/Sentinel.Common` follows SemVer in its `.psd1` `ModuleVersion` /
`ReleaseNotes` (currently `1.1.1`). Bump it per the usual major / minor / patch
rules when the module's API or behaviour changes — independently of the
repository CalVer release it happens to ship with.

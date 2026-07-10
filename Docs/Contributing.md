# Contributing to Sentinel-As-Code

Thank you for your interest in contributing. This guide covers how to report
problems, suggest changes, author content, run the checks, and open a pull
request that will pass the automated gates.

## Code of conduct

Be respectful and considerate in all issues, pull requests, and discussions.
Assume good faith, keep feedback about the work rather than the person, and
report unacceptable behaviour to the maintainers.

## Ways to contribute

### Reporting a bug

1. Search the [issue tracker](https://github.com/noodlemctwoodle/Sentinel-As-Code/issues)
   first; the problem may already be reported.
2. Open a new issue with a clear title and enough to reproduce it:
   - the exact steps, the script or pipeline involved, and the command you ran;
   - the expected behaviour and what actually happened;
   - any error output (redact tenant IDs, subscription IDs, and secrets);
   - your environment (OS, PowerShell version, GitHub Actions or Azure DevOps).

Issues for the companion [Sentinel as Code Toolkit](Toolkit/README.md) are also
raised here, because issues are disabled on the Toolkit repository.

### Suggesting an enhancement

Open a GitHub issue describing the use case. For new detection content, name the
threat scenario and why it matters; for a pipeline or tooling change, say what is
fragile or missing today. Suggest an implementation approach if you have one.

### Contributing content or code

Fork the repository, branch from `main`, and open a pull request (see
[Pull requests](#pull-requests) below). New detection content is authored as YAML
or JSON against the schemas described under [Docs/README.md](README.md) (see the Content section).

## Development environment

- **PowerShell 7.2 or later** is required by every script (Windows PowerShell 5.1
  is not supported).
- **To validate locally you need very little**: Pester, powershell-yaml, and
  Az.Accounts. Everything else the deploy scripts use is mocked in the test suite.
  Run the whole gate with:

  ```powershell
  ./Tools/Invoke-PRValidation.ps1
  ```

- The full module and permission list, split by "needed to validate" versus
  "needed to deploy", is in
  [PowerShell Module Requirements](Deploy/PowerShell-Module-Requirements.md).
- Prefer not to install anything locally? The
  [Build and Test Guide](Guides/Sentinel-As-Code-Build-and-Test-Guide.md) walks
  through browser-based options (Windows 365 Cloud PC, Azure Cloud Shell) end to
  end.

## Authoring conventions

- **Content** is authored to the schemas. The
  [Sentinel as Code Toolkit](Toolkit/README.md) provides schema validation,
  IntelliSense, field-order formatting, and templates for every content type.
- **Path-scoped instructions** under [`.github/instructions/`](../.github/instructions)
  define the schema and conventions for each content type and load automatically
  when you edit a matching file in a Copilot-enabled editor.
- **Prose style**: en-GB spelling (analyse, behaviour, customise), and no
  em-dashes in new prose (use hyphens or parenthetical phrasing). No emoji in
  commit messages, pull request titles, or descriptions.
- **Commit messages** follow conventional-commit format (`type(scope): subject`
  plus a descriptive body). Do **not** add AI or LLM references, and do **not**
  add `Co-Authored-By` trailers. These rules are set out in
  [`AGENTS.md`](../AGENTS.md).

## Testing

- Run the full local gate before opening a pull request:

  ```powershell
  ./Tools/Invoke-PRValidation.ps1
  ```

  It runs every `Tests/*.Tests.ps1` suite plus the dependency-manifest drift
  check. Use `-TestNameFilter '*pattern*'` to run a subset while iterating.
- If you changed KQL content (rules, hunting queries, parsers), regenerate the
  auto-derived dependency graph, or the drift gate will fail the PR:

  ```powershell
  ./Tools/Build-DependencyManifest.ps1 -Mode Generate
  ```

- Where a change affects deployment behaviour, verify it against both Azure
  Commercial and Azure Government as appropriate.
- Test-suite detail and layout are in [Pester Tests](Tests/Pester-Tests.md).

## Pull requests

1. Branch from `main` and open the pull request into `main`.
2. **Fill in the [pull request template](../.github/PULL_REQUEST_TEMPLATE.md).**
   A `template` status check enforces its required sections (Summary, Why, What,
   Testing, and a ticked Type of change), and the five-job validation gate
   (Pester, Bicep build, ARM validation, KQL syntax, dependency-manifest drift)
   must pass before a change can merge.
3. Update the documentation under [`Docs/`](README.md) for any user-visible
   change, and keep no secrets in committed files.
4. One-off setup for the validation gate is documented in
   [PR Validation Setup](Deploy/PR-Validation-Setup.md).

## Versioning

The repository and its releases use **CalVer** (`YY.0M`, for example `26.07`),
**not** Semantic Versioning, and the repository does **not** use git tags:
each release ships as a `release/<CalVer>` branch and a GitHub Release. The one
exception is the in-repo `Sentinel.Common` PowerShell module, which is versioned
with SemVer. Do not bump a "SemVer version number" as part of a content or
pipeline change. The full scheme is in [Versioning](Releases/Versioning.md).

## Recognition

Contributors of community detection rules are acknowledged automatically: an
auto-generated summary is published under `Docs/Content/Community/`. See
[Community Rules](Content/Community-Rules.md) for how to add a contributor.

Thank you for contributing to Sentinel-As-Code.

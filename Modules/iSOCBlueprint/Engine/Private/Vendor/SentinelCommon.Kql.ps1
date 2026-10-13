#Requires -Version 7.2

<#
.SYNOPSIS
    The two KQL helpers the Blueprint uses from Sentinel.Common, carried
    with the module.

.DESCRIPTION
    Remove-KqlComments and Get-KqlBareIdentifiers, copied unchanged from
    Modules/Sentinel.Common/Sentinel.Common.psm1. The collector's
    table-reference captures need them; the shared module also needs
    Az.Accounts and lives outside the iSOCBlueprint module, so a copy keeps
    the module self-contained. Fix them in Sentinel.Common first, then copy
    the function here: Tests/iSOCBlueprint/Vendored.Tests.ps1 fails
    while the two differ.

.NOTES
    File:         Modules/iSOCBlueprint/Engine/Private/Vendor/SentinelCommon.Kql.ps1
    Repository:   Sentinel-As-Code
    Author:       noodlemctwoodle
    Website:      https://sentinel.blog
    Created:      2026-10-13
    Version:      0.1.1
    Last Updated: 2026-10-13
    Requires:     PowerShell 7.2+

    This file defines functions rather than running. Each function's help
    block is the original's.
#>
function Remove-KqlComments {
<#
.SYNOPSIS
    Strip KQL line and block comments from a query string before regex
    extraction so commented-out _GetWatchlist / externaldata calls do
    not produce false positives in the manifest.
#>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string]$Query)

    # Strip /* ... */ block comments first (greedy single-line, lazy
    # multi-line via singleline mode).
    $stripped = [regex]::Replace($Query, '/\*.*?\*/', '', 'Singleline')

    # Strip // line comments to end of line. The negative lookbehind (?<!:)
    # is critical — without it the regex would also match the // in URLs
    # like https://foo.com and chop off the URL host. KQL line comments
    # never legitimately follow a colon (the comment marker has to be
    # whitespace-preceded or at start of line), so excluding ':' is safe.
    $stripped = [regex]::Replace($stripped, '(?<!:)//[^\r\n]*', '')
    return $stripped
}

function Get-KqlBareIdentifiers {
<#
.SYNOPSIS
    Extract bare identifiers that look like table or function references
    in a KQL query — anything that appears at a position where a data
    source is expected (start of a query, after `union`, after `let X =`,
    after `from`, after `|` followed by a data-producing operator like
    `union`, `lookup`, `mv-apply`).

.DESCRIPTION
    Heuristic regex-based extraction. Caller classifies each identifier
    as table-vs-function via the known-functions / known-tables lookups.

    Exclusions baked in: KQL keywords, known operators, single-character
    names (almost certainly let-variable references), let-bound locals,
    lambda parameters, and any identifier appearing inside a string
    literal (e.g. "POP" / "SMTP" in dynamic([...]) blocks must NOT be
    confused with table references).

.OUTPUTS
    String[] of distinct candidate identifiers.
#>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string]$Query)

    if ([string]::IsNullOrWhiteSpace($Query)) { return @() }
    $clean = Remove-KqlComments -Query $Query

    # BEFORE stripping string literals: capture table names passed as
    # string arguments to KQL's `table()` function. Pattern used by
    # lambda wrappers like:
    #
    #   let aadFunc = (tableName: string) { table(tableName) | ... };
    #   let aadSignin = aadFunc("SigninLogs");
    #
    # The actual table identifier ("SigninLogs") never appears as a
    # bare token — only as a string arg to aadFunc, which the lambda
    # forwards to `table()`. Capturing both invocation styles
    # (table('X') / table("X") AND any user-defined function called
    # with a single string arg that the function then forwards to
    # table()) is hard without a real parser; we approximate by
    # capturing every `funcName('X')` and `funcName("X")` where the
    # surrounding query also contains `table(<paramName>)` and the
    # called function's lambda declared <paramName> as a string.
    #
    # Pragmatic compromise: extract string args from any call
    # immediately following an identifier IF the query also contains
    # the literal `table(` token. This produces the right answer for
    # the lambda-table pattern and a small number of false positives
    # (string args to other funcs like _GetWatchlist) — the
    # _GetWatchlist case is already filtered by other rules so it
    # doesn't cause real noise.
    $tableStringRefs = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase)
    if ($clean -match '\btable\s*\(') {
        # Direct table('X') / table("X") calls with a literal name.
        foreach ($m in [regex]::Matches($clean, '\btable\s*\(\s*[''"]([A-Za-z_][A-Za-z0-9_]*)[''"]\s*\)')) {
            [void]$tableStringRefs.Add($m.Groups[1].Value)
        }
        # Indirect: user-defined function called with a string literal.
        # Match `Identifier ( "..." )` and `Identifier ( '...' )` and
        # capture only candidates that look like table names
        # (start with a capital letter, no spaces). Filtering happens
        # at the end via the function-called set so KQL builtins
        # (iff, isempty, replace_regex, etc.) don't slip through.
        foreach ($m in [regex]::Matches($clean, '\b([A-Za-z_][A-Za-z0-9_]*)\s*\(\s*[''"]([A-Z][A-Za-z0-9_]*)[''"]\s*\)')) {
            $candidate = $m.Groups[2].Value
            # Must look like a table — start with capital, contain underscore
            # or be a known table-naming pattern. Conservative filter to
            # avoid grabbing every string that gets passed to a function.
            if ($candidate -cmatch '^[A-Z]' -and $candidate.Length -gt 2) {
                [void]$tableStringRefs.Add($candidate)
            }
        }
    }

    # Strip string literals before any further parsing so identifiers and
    # `;` characters inside strings (e.g. "Other clients; POP") don't
    # become spurious statement-separators or candidate identifiers.
    # Cover both single- and double-quoted strings.
    $clean = [regex]::Replace($clean, '"[^"\r\n]*"', '""')
    $clean = [regex]::Replace($clean, "'[^'\r\n]*'", "''")

    # KQL keywords / operators to exclude from candidate list.
    $kqlKeywords = @(
        'let', 'set', 'where', 'project', 'extend', 'summarize', 'order', 'sort', 'top',
        'take', 'limit', 'distinct', 'count', 'count_', 'as', 'asc', 'desc', 'by',
        'and', 'or', 'not', 'in', 'between', 'contains', 'startswith', 'endswith', 'matches',
        'has', 'has_any', 'has_all', 'hasprefix', 'hassuffix',
        'true', 'false', 'null', 'dynamic', 'datetime', 'timespan', 'string', 'int', 'long',
        'real', 'double', 'bool', 'guid', 'decimal',
        'union', 'join', 'lookup', 'inner', 'leftouter', 'rightouter', 'fullouter',
        'kind', 'isfuzzy', 'on', 'with', 'hint',
        'parse', 'extract', 'split', 'replace', 'strcat', 'tolower', 'toupper', 'tostring',
        'todynamic', 'toint', 'tolong', 'tobool', 'todouble', 'todatetime', 'totimespan',
        'isempty', 'isnotempty', 'isnull', 'isnotnull', 'iif', 'iff', 'case',
        'now', 'ago', 'startofday', 'endofday', 'startofweek', 'endofweek',
        'bin', 'bin_at', 'floor', 'ceiling', 'round', 'abs', 'min', 'max', 'sum', 'avg',
        'arg_max', 'arg_min', 'dcount', 'countif', 'sumif', 'make_list', 'make_set',
        'mv-expand', 'mv-apply', 'mv_expand', 'mv_apply', 'pack', 'pack_array', 'parse-where',
        'render', 'evaluate', 'externaldata', 'materialize', 'find',
        'datatable', 'print', 'range', 'series_decompose', 'series_decompose_anomalies',
        'invoke', 'fork',
        'true', 'false', 'null',
        'series_iir', 'series_seasonal',
        'true', 'false'
    ) | Sort-Object -Unique

    # Identifier candidates appear at three syntactic positions:
    # 1) Start of a query line (column 0 of a stripped line) — a table/function
    #    appearing directly. This is the most common pattern.
    # 2) After `let X = ` — the right-hand side may start with a table.
    # 3) After `union ` (single keyword + space) — table/function being unioned.
    # We extract from each position with separate regexes, then dedupe.
    $candidates = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )

    # Position 1: first data-source identifier per statement.
    #
    # Naive "any identifier at start of a line" is too noisy — KQL queries
    # routinely have column names appearing on continuation lines after
    # `project` / `extend` / `summarize ... by`. The discriminator: a table
    # reference appears at the BEGINNING of a statement, where statements
    # are delimited by `;` (KQL's statement terminator). Within each
    # statement, the first identifier is either the table directly or the
    # RHS of a `let X =` binding.
    $statements = $clean -split ';'
    foreach ($stmt in $statements) {
        if ([string]::IsNullOrWhiteSpace($stmt)) { continue }
        # `let X = TableName ...` → capture TableName
        if ($stmt -match '(?ms)^\s*(?:declare\s+\(.*?\)\s+)?let\s+\w+\s*=\s*\(?\s*([A-Za-z_][A-Za-z0-9_]*)\b') {
            [void]$candidates.Add($Matches[1])
        }
        # Otherwise first identifier in the statement.
        elseif ($stmt -match '(?ms)^\s*([A-Za-z_][A-Za-z0-9_]*)\b') {
            [void]$candidates.Add($Matches[1])
        }
    }

    # Position 2: after `union ` keyword (skipping any number of
    # `key=value` modifiers like `kind=outer`, `isfuzzy=true`, `hint.*=...`).
    foreach ($m in [regex]::Matches($clean, '\bunion\s+(?:[\w.]+\s*=\s*\w+\s+)*([A-Za-z_][A-Za-z0-9_]*)\b')) {
        [void]$candidates.Add($m.Groups[1].Value)
    }

    # Position 3: subquery start after a join/lookup operator. Pattern:
    #     | join kind=inner (TableName | where ...)
    #     | lookup (TableName | project ...)
    foreach ($m in [regex]::Matches($clean, '\b(?:join|lookup)\s+(?:kind\s*=\s*\w+\s+)?\(\s*([A-Za-z_][A-Za-z0-9_]*)\b')) {
        [void]$candidates.Add($m.Groups[1].Value)
    }

    # Position 4: subquery start inside a paren-wrapped block following
    # one of the KQL operators that take a tabular subquery argument:
    #     materialize (TableName | ...)
    #     view (TableName | ...)
    #     toscalar (TableName | ...)
    # The operator names themselves are KQL keywords filtered out at the
    # end; what we want is the first identifier inside the paren.
    foreach ($m in [regex]::Matches($clean, '\b(?:materialize|view|toscalar)\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)\b')) {
        [void]$candidates.Add($m.Groups[1].Value)
    }

    # Add the table-string refs collected from `table('X')` / lambda
    # forwarding patterns BEFORE the keyword/function-call filter runs.
    foreach ($r in $tableStringRefs) { [void]$candidates.Add($r) }

    # Drop candidates that are immediately followed by an opening paren
    # in the source — those are KQL function calls (e.g. `toscalar(...)`,
    # `_GetWatchlist(...)`, `materialize(...)`, `iff(...)`), not data
    # sources. Build a set of "known to be function-called" names by
    # regex over the original query.
    $functionCalled = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    foreach ($m in [regex]::Matches($clean, '\b([A-Za-z_][A-Za-z0-9_]*)\s*\(')) {
        [void]$functionCalled.Add($m.Groups[1].Value)
    }

    # Drop candidates that are LHS of a `let X =` binding OR a parameter
    # of a let-defined lambda — both are locally-scoped, not external
    # dependencies. Lambda parameters look like:
    #     let aadFunc = (tableName: string, start: datetime) { ... }
    $letBindings = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    foreach ($m in [regex]::Matches($clean, '(?m)^\s*let\s+(\w+)\s*=')) {
        [void]$letBindings.Add($m.Groups[1].Value)
    }
    # Lambda parameter detection: capture the param-list inside
    # `let X = ( ... ) { ... }` and split on `,` to get individual
    # `paramName: type` declarations.
    foreach ($m in [regex]::Matches($clean, '(?ms)\blet\s+\w+\s*=\s*\(([^)]+)\)\s*\{')) {
        $paramList = $m.Groups[1].Value
        foreach ($paramMatch in [regex]::Matches($paramList, '([A-Za-z_][A-Za-z0-9_]*)\s*:')) {
            [void]$letBindings.Add($paramMatch.Groups[1].Value)
        }
    }

    # Filter: drop KQL keywords/operators, function-call sites, let-bound
    # locals, and obvious single-character names.
    $filtered = @($candidates | Where-Object {
        $_.Length -gt 1 -and
        ($kqlKeywords -notcontains $_.ToLowerInvariant()) -and
        (-not $functionCalled.Contains($_)) -and
        (-not $letBindings.Contains($_))
    } | Sort-Object -Unique)

    return $filtered
}

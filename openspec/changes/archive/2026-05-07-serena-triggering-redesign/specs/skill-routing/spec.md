## ADDED Requirements

### Requirement: Serena Grep Matcher Regex Coverage

The `serena-nudge.sh` hook MUST classify Grep patterns of the following shapes as symbol lookups and emit `additionalContext` recommending Serena MCP tools: word-boundary identifiers (`\bIdent\b`, `^Ident$`), dotted or qualified member access (`Foo\.bar`, `Foo::bar`), and embedded definition-prefix patterns (`^class +Foo\b`, `def +process_\w+`). The hook MUST NOT emit additionalContext when the pattern contains heavy alternation (3 or more alternatives), lookaround constructs, or character classes containing whitespace.

#### Scenario: Word-boundary symbol fires the nudge

- **GIVEN** `serena=true`
- **WHEN** Claude calls `Grep` with pattern `\bUserService\b`
- **THEN** the PreToolUse hook MUST emit `additionalContext` recommending `find_symbol` or `get_symbols_overview`

#### Scenario: Dotted member access fires the nudge

- **GIVEN** `serena=true`
- **WHEN** Claude calls `Grep` with pattern `Foo::bar` or `User\.profile`
- **THEN** the hook MUST emit `additionalContext` recommending Serena symbol tools

#### Scenario: Definition prefix fires regardless of regex wrapping

- **GIVEN** `serena=true`
- **WHEN** Claude calls `Grep` with pattern `^class +Foo\b`
- **THEN** the hook MUST emit `additionalContext` recommending Serena symbol tools

#### Scenario: Free text and broad character classes do not fire

- **GIVEN** `serena=true`
- **WHEN** Claude calls `Grep` with pattern `Connection refused` or `[A-Za-z 0-9_-]+ failed`
- **THEN** the hook MUST NOT emit any `additionalContext`

### Requirement: Serena Telemetry Append-Only Log

When the Grep nudge fires, the hook MUST append a tab-separated record to `~/.claude/.serena-nudge-telemetry` containing six fields: unix timestamp, session token, turn id, kind (`nudge`), matcher name (`grep_extension`), and pattern class. Telemetry writes MUST be opt-out via the `SERENA_TELEMETRY=0` environment variable. A failed write MUST NOT cause the hook to exit non-zero.

#### Scenario: Telemetry is appended on fire

- **GIVEN** `SERENA_TELEMETRY` is unset and the Grep matcher fires on pattern `\bUserService\b`
- **WHEN** the hook completes
- **THEN** `~/.claude/.serena-nudge-telemetry` MUST contain a line with `nudge`, `grep_extension`, and `word_boundary`

#### Scenario: Telemetry is suppressed by env flag

- **GIVEN** `SERENA_TELEMETRY=0` and the Grep matcher fires
- **WHEN** the hook completes
- **THEN** no telemetry line MUST be written

### Requirement: Silent Missed-Opportunity Observers

The `serena-observer.sh` hook MUST run on `Read`, `Glob`, and `Edit` PreToolUse events when `serena=true` and silently log candidate missed-opportunity observations to the same telemetry file used by the active matcher. The hook MUST NOT emit any `additionalContext` for any input. The observer MUST classify:

- `read_large_source`: Read of a source-code file (one of `.ts|.tsx|.js|.jsx|.py|.go|.rs|.java|.kt|.scala|.rb|.cs|.cpp|.cc|.c|.h|.hpp|.swift|.m|.mm`) with no `offset` or `limit` field and more than 500 lines.
- `glob_definition_hunt`: Glob pattern containing a CamelCase token between `*` wildcards, excluding patterns matching `*.md*|*.json*|*.yaml*|*.yml*|*.lock*|*.test.*|*.spec.*`.
- `edit_symbol_token`: Edit on a source file where both `old_string` and `new_string` are single-line bare identifiers and differ.

#### Scenario: Read on >500-line source file logs observation

- **GIVEN** `serena=true` and a 600-line `.ts` file
- **WHEN** Claude calls `Read` on the file with no `offset`/`limit`
- **THEN** the observer MUST append an `observe` line with class `read_large_source` to telemetry
- **AND** the observer MUST NOT emit `additionalContext`

#### Scenario: Glob on broad inventory does not log

- **GIVEN** `serena=true`
- **WHEN** Claude calls `Glob` with pattern `**/*.md` or `**/*.test.ts`
- **THEN** no observation MUST be logged

#### Scenario: Edit single-symbol diff in source logs observation

- **GIVEN** `serena=true` and a `.ts` file
- **WHEN** Claude calls `Edit` with `old_string=UserService` and `new_string=AccountService`
- **THEN** the observer MUST log an `observe` line with class `edit_symbol_token`

### Requirement: Follow-Through Correlator

The `serena-followthrough.sh` hook MUST run on PostToolUse for tools matching `^mcp__serena__` and append a `followup` record for each unmarked nudge or observation in the same session that occurred within 3 turns. Correlation MUST be idempotent: a `(turn, matcher)` pair already followed up MUST NOT generate a duplicate record. The correlator MUST NOT emit followups for errored Serena tool results.

#### Scenario: Serena call within 3 turns of nudge correlates

- **GIVEN** a `nudge` record at turn 5 in session token T
- **WHEN** `mcp__serena__find_symbol` returns successfully at turn 6 in session T
- **THEN** a `followup` line MUST be appended carrying the original matcher and the Serena tool name

#### Scenario: No double-correlation on repeat Serena calls

- **GIVEN** a `nudge` already correlated to a `followup` record
- **WHEN** another Serena tool call occurs in the same window
- **THEN** no additional `followup` line MUST be appended for the same `(turn, matcher)` pair

#### Scenario: Cross-session noise does not evict our window

- **GIVEN** a `nudge` for session T followed by 250 telemetry lines from concurrent sessions
- **WHEN** Serena tool returns for session T within 3 turns
- **THEN** the followup MUST still be appended (token-filter happens before line cap)

### Requirement: Subagent Guidance Propagation

The SessionStart Serena banner MUST instruct the parent context to propagate Serena guidance into Task spawn prompts. The instruction MUST be included only when `serena=true` and MUST name the propagated guidance string verbatim. The banner MUST NOT mention `mcp__serena__get_diagnostics_for_file`; the two-pole rule (LSP for diagnostics, Serena for navigation) is preserved.

#### Scenario: Banner instructs propagation when serena is enabled

- **GIVEN** `serena=true` in the session capabilities
- **WHEN** the SessionStart hook runs
- **THEN** the emitted `additionalContext` MUST mention `Task tool` and the literal string `Serena available`

#### Scenario: Banner does not surface third-pole diagnostics

- **WHEN** the SessionStart hook runs with `serena=true` and `lsp=true`
- **THEN** the emitted banner MUST mention `mcp__ide__getDiagnostics` for diagnostics
- **AND** the banner MUST NOT mention `get_diagnostics_for_file`

### Requirement: Telemetry Rolling-Window Report

The `scripts/serena-telemetry-report.sh` script MUST summarise per-class follow-through percentages over a rolling window (default 14 days). The report MUST include `firings`, `followups`, and `pct` columns for every observed class. When telemetry is empty or missing, the script MUST emit a recognisable empty-state message rather than fail.

#### Scenario: Per-class percentages are computed correctly

- **GIVEN** 10 `nudge` records and 5 `followup` records for class `grep_extension` within the window
- **WHEN** the report runs with `days=14`
- **THEN** the output MUST contain `grep_extension` with `50%` follow-through

#### Scenario: Empty telemetry produces empty-state output

- **GIVEN** `~/.claude/.serena-nudge-telemetry` does not exist or is empty
- **WHEN** the report runs
- **THEN** the output MUST contain `no telemetry`

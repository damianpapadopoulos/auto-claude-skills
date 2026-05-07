# Tasks: Serena Triggering Redesign

## Completed

- [x] 1.1 Add failing tests for the broadened Grep regex coverage (`tests/test-serena-nudge.sh`).
- [x] 1.2 Extend `hooks/serena-nudge.sh` to handle regex word-boundary, dotted/qualified, and embedded definition-prefix patterns; add telemetry write on fire.
- [x] 2.1 Add failing tests for the silent observer (`tests/test-serena-observer.sh`).
- [x] 2.2 Implement `hooks/serena-observer.sh` and wire it into `hooks/hooks.json` PreToolUse `Read|Glob|Edit`.
- [x] 3.1 Add failing tests for the follow-through correlator (`tests/test-serena-followthrough.sh`).
- [x] 3.2 Implement `hooks/serena-followthrough.sh` and wire it into `hooks/hooks.json` PostToolUse `^mcp__serena__`.
- [x] 4.1 Add failing tests for the SessionStart banner edits (`tests/test-session-start-banner.sh`).
- [x] 4.2 Update SessionStart banner to instruct subagent prompt propagation (`hooks/session-start-hook.sh:1101-1104`).
- [x] 5.1 Add failing tests for the telemetry-report script (`tests/test-serena-telemetry-report.sh`).
- [x] 5.2 Implement `scripts/serena-telemetry-report.sh`.
- [x] 6 Add behavioral eval fixture for the broadened Grep matcher (`tests/fixtures/evals/serena-grep-patterns.json`).
- [x] 7 Update `CHANGELOG.md` with the redesign entry under `[Unreleased]`.
- [x] 8 Code review fixes:
  - [x] 8.1 `serena-followthrough.sh` filters telemetry by token before `tail -200` (prevents cross-session eviction).
  - [x] 8.2 `serena-followthrough.sh` `_SEEN` dedup key uses tab separator (matcher names cannot contain tabs by TSV invariant).
  - [x] 8.3 Add multi-session regression test in `tests/test-serena-followthrough.sh`.

All 42 test files in `tests/run-tests.sh` pass.

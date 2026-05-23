# Tasks: Serena Auto-Register on First Session

## Completed

- [x] 1.1 Write failing unit tests for `serena_maybe_autoregister` (`tests/test-serena-autoregister.sh`, 7 tests, mocked `serena`/`claude` binaries on PATH) — commit `36536bb`
- [x] 1.2 Implement `hooks/lib/serena-autoregister.sh` exposing `serena_maybe_autoregister` (Bash 3.2 compatible, jq-free, fail-open) — commit `1bb5dd6`
- [x] 1.3 Amend the registration command to include `--open-web-dashboard false` (per-MCP-server dashboard suppression) — commit `6f10da0`
- [x] 1.4 Wire library into `hooks/session-start-hook.sh` before the `context_capabilities` augmentation block + add integration test in `tests/test-registry.sh` (3 assertions including dashboard-flag regression guard) — commit `1faee5e`
- [x] 1.5 Gate the wiring under `_SKILL_TEST_MODE != 1` (with `_SKILL_TEST_AUTOREG=1` escape hatch for the integration test) to prevent real `claude mcp add` from polluting test tmpdir HOMEs — commit `2bad739`
- [x] 1.6 Document the marker as the recovery path + the `--open-web-dashboard false` flag + how to opt the browser tab back in via `~/.claude.json` (`commands/setup.md`) — commit `bf90976`
- [x] 1.7 Add `[Unreleased]` `### Added` entry to `CHANGELOG.md` — commit `dc221b1`
- [x] 1.8 Manual smoke test on real binary: marker writes, `[serena-autoregister]` breadcrumb emits, second run is silent no-op (marker prevents re-run), full test suite passes (48/48 files)

# Bug-Fix Batch Design — 2026-03-23

## Context

Thorough audit of auto-claude-skills codebase identified 9 actionable bugs across
the routing engine, session-start hook, registry JSON, skill triggers, and supporting hooks.
All bugs have confirmed root causes and clear fixes.

## Fixes (priority order)

### Fix 1: Field count mismatch ✅ DONE
- **File:** `hooks/skill-activation-hook.sh:104`
- **Root cause:** jq produces 9 `\x1f` fields; `read` consumes 8. `required_when` contaminates `keywords_joined`.
- **Fix:** Add `_required_when` as 9th variable to `read`.

### Fix 2: Tests mutate fallback-registry.json — IN PROGRESS
- **Files:** `hooks/session-start-hook.sh:778`, `tests/test-registry.sh:22`
- **Root cause:** Test `run_hook` sets `CLAUDE_PLUGIN_ROOT` to source tree; hook auto-regenerates fallback with machine-specific data.
- **Fix:** Guard fallback write with `_SKILL_TEST_MODE` env var. Clean committed fallback: remove 2 runtime-discovered skills (`test-driven-development`, `using-superpowers`), keep generous defaults (bundled skills `available: true`, external `available: false`).

### Fix 3: Test registry drift
- **File:** `tests/test-routing.sh` `install_registry` function
- **Root cause:** Priorities diverged: `systematic-debugging` 10→50, `executing-plans` 15→35. `brainstorming` triggers missing word-boundary guards.
- **Fix:** Sync test fixture priorities and triggers with `config/default-triggers.json`.

### Fix 4: Overly broad triggers
- **File:** `config/default-triggers.json`
- **Root cause:** Bare `measure` in outcome-review matches implementation prompts. Bare `discover` in product-discovery matches "I discovered a bug".
- **Fix:** Tighten: `measure` → require follow-on context word; `discover` → require discovery-specific suffix. Add false-positive guard tests.

### Fix 5: Hints filter asymmetry
- **File:** `hooks/skill-activation-hook.sh:1198`
- **Root cause:** Hints jq block requires `.plugin` unconditionally; parallel/sequence have `if .plugin then ... else ... end`.
- **Fix:** Add same guard to hints block.

### Fix 6: Non-atomic cache writes + JSON injection
- **Files:** `session-start-hook.sh:772,783,788`, `skill-activation-hook.sh:963`
- **Root cause:** Cache writes truncate-then-write (not atomic). Signal file uses `printf %s` instead of `jq` for JSON.
- **Fix:** Write to `.tmp.$$` then `mv` for atomicity. Use `jq -n --arg` for signal file.

### Fix 7: Dead code + unknown role fallthrough + grep -qF
- **Files:** Both hooks
- **Root cause:** `COMPOSITION_NEXT`, `SOURCE_COUNT` unused. Unknown roles bypass caps. `grep -q` treats skill names as regex.
- **Fix:** Remove dead vars. Add `*) continue ;;`. Use `grep -qF`.

### Fix 8: Missing keywords field + compact-recovery fail-open
- **Files:** `config/default-triggers.json`, `hooks/compact-recovery-hook.sh`
- **Root cause:** `security-scanner` missing `keywords: []`. Hook has no `trap 'exit 0' ERR`.
- **Fix:** Add field. Add trap.

### Fix 9: Frontmatter parser backslash escaping
- **File:** `hooks/session-start-hook.sh` awk parser
- **Root cause:** Only `"` escaped, not `\`. Backslash in frontmatter values produces invalid JSON.
- **Fix:** Add `gsub(/\\/, "\\\\", val)` before double-quote escape.

## Testing Strategy

Each fix follows TDD: write failing test → implement fix → verify green → verify no regressions.
Final verification: `bash tests/run-tests.sh` all green.

## Scope Boundaries

- No refactoring beyond the bug fix
- No new features
- Session token race condition (concurrent sessions) deferred — requires architectural change
- Performance budget (34 jq forks) deferred — requires batching redesign

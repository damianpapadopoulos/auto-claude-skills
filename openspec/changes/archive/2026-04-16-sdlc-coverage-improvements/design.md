# Design: SDLC Coverage Improvements (Tasks 0-1)

## Architecture

### Routing Interaction Tests
The test harness follows the established pattern from `test-routing.sh`: JSON input piped to the activation hook, `hookSpecificOutput.additionalContext` extraction, and `setup_test_env`/`teardown_test_env` lifecycle from `test-helpers.sh`. A self-contained `install_registry()` function provides a production-accurate registry with 24 skills covering all collision groups.

Key helpers: `assert_activates` (skill name appears in context), `assert_does_not_activate` (skill name absent), `section` (group delimiter).

### Artifact Contract
Session state fields flow through `openspec_state_upsert_change()` → state file → `openspec_write_provenance()` → `source.json`. The function now writes both canonical (`design_path`, `plan_path`, `spec_path`) and legacy (`sp_plan_path`, `sp_spec_path`) field names in the same jq template. The provenance writer reads with `//` fallback chains for bidirectional compatibility.

Intent Truth retrieval uses a 5-tier cascade: OpenSpec active changes → `docs/plans/` live artifacts → `openspec/specs/` canonical → `docs/plans/archive/` → `docs/superpowers/specs/` legacy.

## Dependencies
No new dependencies. Existing: jq, bash 3.2, test-helpers.sh.

## Decisions & Trade-offs

1. **Production-accurate test registry vs. minimal registry:** Used a full 24-skill registry in tests to detect real collisions, rather than testing with a minimal subset. Trade-off: larger test file (~600 lines), but catches priority/phase-gating interactions that a minimal registry would miss.

2. **`required` role phase-gating documented in tests:** Tests for `using-git-worktrees` document that the `required` role only activates when tentative phase matches the skill's phase. When brainstorming sets phase to DESIGN, IMPLEMENT-phase required skills are excluded. Tests assert what the engine *does*, not what a naive reader might *expect*.

3. **Dual-write for backward compatibility:** Both canonical and legacy field names are written on every upsert. This costs ~50 bytes per entry but eliminates any migration window where old code reads empty fields.

4. **`docs/plans/` before `openspec/specs/` in retrieval:** Live intent artifacts (current session's design) take precedence over post-ship canonical specs because during active development the design document is more current than whatever was archived previously.

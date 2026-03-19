# Tasks: Incident Analysis

## Completed

- [x] 1. Create `skills/incident-analysis/SKILL.md` — 210-line skill with frontmatter, 4 behavioral constraints, 3-stage state machine, tiered tool detection, LQL cheat sheet, postmortem schema
- [x] 2. Update routing triggers in `config/default-triggers.json` — expanded `gcp-observability` hint + new `incident-analysis` skill entry (domain, priority 20)
- [x] 3. Verify fallback-registry auto-regeneration — confirmed `session-start-hook.sh` auto-syncs correctly
- [x] 4. Add observability_capabilities to `hooks/session-start-hook.sh` — gcloud detection (Step 8g) + emission after Security tools line
- [x] 5. Add Observability Truth to `skills/unified-context-stack/phases/testing-and-debug.md` — Section 4 with Tier 1/2/3 guidance
- [x] 6. Add 6 routing tests to `tests/test-routing.sh` — hint triggers, skill scoring, phase gating, trigger preservation, source correctness, invoke path
- [x] 7. Full test suite verification — 243/243 routing tests pass, 0 regressions

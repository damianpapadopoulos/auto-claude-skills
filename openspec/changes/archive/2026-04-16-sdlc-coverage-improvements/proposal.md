## Why
The auto-claude-skills plugin had four artifact namespaces for design intent (`docs/superpowers/plans/`, `docs/superpowers/specs/`, `openspec/specs/`, `openspec/changes/`) with no unified retrieval precedence, and 0.39 test scenarios per skill for routing collision detection. This created two risks: (1) Claude might read stale or wrong intent artifacts during development, and (2) trigger pattern collisions between skills went undetected.

## What Changes
Two changes shipped from the SDLC coverage improvements plan (Tasks 0 and 1 of 5):

1. **Routing interaction regression tests** — 39 tests across 5 collision groups validating that overlapping trigger patterns route to the correct skill. Covers code-review vs agent-team-review, parallel-agents vs git-worktrees, systematic-debugging vs incident-analysis, cross-phase ambiguity, and negative routing.

2. **Canonical artifact contract** — Unified `docs/plans/` as the primary intent namespace with a 5-tier retrieval precedence. Added `design_path` and canonical `plan_path`/`spec_path` session state fields with legacy `sp_plan_path`/`sp_spec_path` aliases for backward compatibility.

## Capabilities

### Modified Capabilities
- `skill-routing`: Added 39 interaction regression tests for trigger collision detection
- `intent-truth`: Updated from 3-source to 5-tier retrieval precedence with `docs/plans/` as canonical live intent source
- `openspec-ship`: Updated to canonical `docs/plans/` paths with `docs/plans/archive/` intent archival step
- `session-state`: Added `design_path`, canonical `plan_path`/`spec_path` fields with backward-compatible legacy aliases

## Impact
- `hooks/lib/openspec-state.sh`: New `design_path` parameter (6th, optional) in `openspec_state_upsert_change`; provenance writer now includes canonical + legacy field names
- `hooks/skill-activation-hook.sh`: Plan-path warning updated from `docs/superpowers/plans/` to `docs/plans/`
- `skills/unified-context-stack/`: Intent Truth tier document rewritten; 3 phase documents updated with new precedence order
- `skills/openspec-ship/SKILL.md`: Session state field references, path examples, skip criteria, and archival section updated
- `skills/agent-team-review/SKILL.md`: Context gathering paths updated with acceptance spec and legacy fallback
- `tests/`: New `test-routing-interactions.sh` (39 tests); `test-openspec-state.sh` updated (+6 assertions for new fields)

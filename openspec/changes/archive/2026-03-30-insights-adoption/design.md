# Design: Insights Adoption

## Architecture
Two independent subsystems added to existing infrastructure:

1. **Observability preflight** (`scripts/obs-preflight.sh`): A standalone bash script that outputs JSON status for gcloud, kubectl, and observability MCP. Invoked on-demand by skill docs (not at session start) to respect the 200ms session-start budget. Skills parse the JSON to select their execution tier.

2. **REVIEW guard** (Check 4 in `hooks/openspec-guard.sh`): Extends the existing PreToolUse hook that fires on `git commit`/`git push` during SHIP phase. Reads `.skill-composition-state-{TOKEN}` to check if `requesting-code-review` appears in the chain but not in completed. Emits a warning (fail-open, never blocks).

## Dependencies
No new dependencies. Uses existing jq, bash, and the test-helpers.sh framework.

## Decisions & Trade-offs

**On-demand vs session-start preflight:** The external analysis initially recommended session-start placement. This was corrected based on the 200ms budget constraint in CLAUDE.md. On-demand invocation (only when incident-analysis/alert-hygiene/investigate activates) avoids penalizing sessions that never touch observability.

**Extend openspec-guard vs new hook:** The REVIEW guard reuses the existing openspec-guard.sh rather than creating a separate hook. This reduces hook count, shares the SHIP-phase gating logic, and keeps all pre-commit checks in one place.

**What was dropped:** The insights doc suggested an /sdlc custom skill, headless git maintenance, phase-per-agent supervisor pipeline, and several CLAUDE.md additions already covered by existing routing. All were rejected as redundant with shipped capabilities or architecturally wrong for Claude Code's execution model.

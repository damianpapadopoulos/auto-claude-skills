## Why
A Claude Code Insights analysis of 107 sessions identified recurring friction points: unnecessary clarification prompts, full-file rewrites causing data loss, missing auth/tool checks before observability workflows, and skipped REVIEW phases before SHIP. Two analyses (one internal, one external) converged on four actionable improvements that compose cleanly with existing architecture.

## What Changes
Four improvements adopted from the insights analysis:
1. Two CLAUDE.md instructions: "proceed means continue" (reduces friction) and "no full-file rewrites" (prevents data loss).
2. On-demand observability preflight script (`scripts/obs-preflight.sh`) that checks gcloud auth, kubectl connectivity, and observability MCP configuration before data-heavy workflows.
3. Preflight wired into incident-analysis, alert-hygiene, and /investigate skill docs as the first step before tier selection.
4. REVIEW-before-SHIP guard in `openspec-guard.sh` that reads composition state and warns when `requesting-code-review` was skipped.

## Capabilities

### Modified Capabilities
- `auto-claude-skills`: Added observability preflight helper, REVIEW guard, and CLAUDE.md behavioral constraints

## Impact
- `CLAUDE.md`: Two new behavioral rules for all sessions
- `scripts/obs-preflight.sh`: New shared script invoked by 3 skill docs
- `hooks/openspec-guard.sh`: Extended with Check 4 (composition-state-aware REVIEW guard)
- `skills/incident-analysis/SKILL.md`: Step 1 now runs preflight before tier detection
- `skills/alert-hygiene/SKILL.md`: Tier Detection section now runs preflight before data access
- `commands/investigate.md`: New preflight step before Stage 1 entry
- `tests/test-obs-preflight.sh`: 9 new tests (13 assertions)
- `tests/test-openspec-state.sh`: 4 new REVIEW guard tests
- `tests/test-skill-content.sh`: 3 new content assertions

## Why

The plugin had security-scanner (SAST), agent-safety-review (design-time), and implementation-drift-check (spec drift), but no behavioral governance review at review time. Small changes (1-4 files) passed through requesting-code-review with no adversarial lens. The plugin's own governance model had no regression tests.

## What Changes

Three-component governance layer at review time:

1. **Always-on adversarial checklist** — 6-point governance check as REVIEW composition hint. Fires on every code review. Checks for HITL bypass, scope expansion, safety gate weakening, bypass patterns, and hook/config changes.
2. **Adversarial-reviewer specialist** — 4th reviewer template in agent-team-review, spawned alongside security/quality/spec reviewers for 5+ file changes. Focused on governance regressions.
3. **Adversarial eval fixtures** — 4 routing scenario fixtures testing governance-sensitive prompts + 10-assertion content test validating governance constraints in key skills.

## Capabilities

### New Capabilities
- `adversarial-review`: Always-on governance checklist in REVIEW composition and adversarial-reviewer specialist in agent-team-review for behavioral governance review at review time

### Modified Capabilities
- `agent-team-review`: Extended from 3 to 4 reviewer templates (added adversarial-reviewer with governance lens)
- `REVIEW composition`: Added always-on adversarial checklist hint

## Impact

- **Skills modified:** agent-team-review (SKILL.md — new template + table + FINDING category)
- **Config modified:** default-triggers.json, fallback-registry.json (REVIEW hints)
- **New files:** 1 test file (test-adversarial-governance.sh), 4 scenario fixtures (adversarial-19 through 22)
- **Zero Superpowers files modified**

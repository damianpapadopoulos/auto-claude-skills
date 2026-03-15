# Design: Phase-Aware RED FLAGS + Enforcement Hint

## Overview

Extend the RED FLAGS mechanism (currently only SHIP/verification) to all SDLC phases. Add a methodology hint that fires during DESIGN/PLAN when implementation-intent language appears. Fix the security-scanner test assertion (issue 4).

## Motivation

The model repeatedly skips SDLC phases when changes feel "small" — jumping from a user question directly to editing files without going through brainstorming → writing-plans → executing-plans. The existing RED FLAGS mechanism for verification-before-completion is the one enforcement pattern the model consistently respects. Extending it to all phases follows the superpowers pattern (instruction-level enforcement, not programmatic blocking) and uses a proven mechanism.

Design debate conclusion: RED FLAGS + methodology hint is the right approach. PreToolUse hooks are too aggressive (file classification is fuzzy, breaks legitimate DESIGN-phase writes). Doing nothing is insufficient (model demonstrably ignores current instructions). The critic's state-machine idea (tracking phase completion) is tracked for future escalation if RED FLAGS prove insufficient.

## 1. Phase-Aware RED FLAGS

### Location

`hooks/skill-activation-hook.sh` — `_format_output()`, alongside the existing SHIP RED FLAGS block.

### RED FLAGS by phase

**DESIGN:**
```
HALT if any Red Flag is true:
- Editing implementation files before invoking Skill(superpowers:brainstorming)
- Skipping design presentation and user approval
- Jumping to writing code without exploring approaches first
- Not writing a design doc before transitioning to PLAN
```

**PLAN:**
```
HALT if any Red Flag is true:
- Editing implementation files before invoking Skill(superpowers:writing-plans)
- Implementing without an approved plan document
- Skipping TDD steps in the plan
- Not saving the plan to docs/superpowers/plans/ before executing
```

**IMPLEMENT:**
```
HALT if any Red Flag is true:
- Implementing on main without setting up a git worktree first
- Skipping TDD: writing implementation before writing the failing test
- Not following the plan step by step
- Jumping to SHIP without going through REVIEW (requesting-code-review) first
- Use subagent-driven-development or agent-team-execution where appropriate
```

**REVIEW:**
```
HALT if any Red Flag is true:
- Summarizing changes instead of dispatching superpowers:code-reviewer subagent
- Not providing BASE_SHA and HEAD_SHA git diff range to the reviewer
- Claiming review is complete without acting on critical/important findings
- Skipping security-scanner during review
```

**SHIP:** Already present (verification checklist). No change.

**DEBUG:** No RED FLAGS — debugging is ad-hoc by design.

### Injection logic

In `_format_output()`, after the existing SHIP RED FLAGS block, add phase-specific RED FLAGS based on `PRIMARY_PHASE`. The RED FLAGS are appended to `SKILL_LINES` (same mechanism as the existing verification RED FLAGS).

```bash
case "$PRIMARY_PHASE" in
  DESIGN) RED_FLAGS="..." ;;
  PLAN)   RED_FLAGS="..." ;;
  IMPLEMENT) RED_FLAGS="..." ;;
  REVIEW) RED_FLAGS="..." ;;
esac
```

The existing SHIP RED FLAGS block (which checks for `verification-before-completion` in SELECTED) remains unchanged.

## 2. Phase Enforcement Methodology Hint

### Location

`config/default-triggers.json` — `methodology_hints[]`

### Definition

```json
{
  "name": "phase-enforcement",
  "triggers": [
    "(fix|change|update|rename|move|add a|modify|edit|refactor|implement|write the|create the)"
  ],
  "trigger_mode": "regex",
  "hint": "PHASE ENFORCEMENT: You are in DESIGN/PLAN phase. Complete the current phase skill before editing implementation files. Small changes still require the full flow — scaled down, not skipped.",
  "phases": ["DESIGN", "PLAN"]
}
```

This fires only during DESIGN/PLAN phases when implementation-intent language appears in the prompt. It reinforces the RED FLAGS with a methodology-level reminder.

## 3. REVIEW Phase Sequencing Clarification

### Problem

The REVIEW phase has three skills but their relationship is unclear in the hook output:

- `requesting-code-review` (process) — dispatches the code-reviewer subagent
- `receiving-code-review` (process) — processes review feedback with technical rigor
- `agent-team-review` (required, conditional) — dispatches parallel specialist reviewers

The model doesn't know:
- That `receiving-code-review` exists as a follow-up to `requesting-code-review`
- Whether `agent-team-review` runs alongside or after `requesting-code-review`

### Fix

Update the REVIEW `phase_compositions.sequence` to describe the full flow:

```json
"sequence": [
  {
    "step": "requesting-code-review",
    "purpose": "Get BASE_SHA and HEAD_SHA. Dispatch superpowers:code-reviewer subagent with diff and plan reference. Fix critical/important issues."
  },
  {
    "step": "agent-team-review",
    "purpose": "For substantial changes (3+ files, cross-module, security-sensitive): dispatch parallel specialist reviewers alongside code-reviewer."
  },
  {
    "step": "receiving-code-review",
    "purpose": "Process reviewer findings with technical rigor. Verify claims against codebase. Push back if wrong. Fix issues one at a time."
  }
]
```

This makes the ordering explicit: dispatch reviewers first (requesting + agent-team), then process their feedback (receiving).

## 4. Security-Scanner Test Fix (Issue 4)

### Location

`tests/test-context.sh` — `test_security_scanner_review_parallel()`

### Change

Tighten the PARALLEL assertion from `grep -c 'PARALLEL:.*security-scanner'` to `grep -c 'PARALLEL:.*security-scanner.*Skill(security-scanner)'` to validate that the composition jq rendered the invoke pattern, not just the skill name.

## 4. Files to Modify

| File | Change |
|------|--------|
| `hooks/skill-activation-hook.sh` | Add phase-aware RED FLAGS in `_format_output()` for DESIGN, PLAN, IMPLEMENT, REVIEW |
| `config/default-triggers.json` | Add `phase-enforcement` methodology hint; update REVIEW sequence with 3-step flow (requesting → agent-team → receiving) |
| `tests/test-context.sh` | Tighten security-scanner assertion |
| `tests/test-routing.sh` | Add tests verifying RED FLAGS appear at each phase |
| `config/fallback-registry.json` | Regenerate |

## 5. Tests

1. **DESIGN RED FLAGS present** — Prompt triggering DESIGN phase. Assert output contains "Editing implementation files before invoking" RED FLAG.
2. **PLAN RED FLAGS present** — Prompt triggering PLAN phase. Assert output contains "Implementing without an approved plan" RED FLAG.
3. **IMPLEMENT RED FLAGS present** — Prompt triggering IMPLEMENT phase. Assert output contains "Implementing on main without" RED FLAG.
4. **REVIEW RED FLAGS present** — Prompt triggering REVIEW phase. Assert output contains "Summarizing changes instead of dispatching" RED FLAG.
5. **Phase enforcement hint fires** — DESIGN phase + implementation-intent prompt. Assert hint text present.
6. **Phase enforcement hint does NOT fire at IMPLEMENT** — IMPLEMENT phase + implementation-intent prompt. Assert hint NOT present.
7. **Security-scanner test tightened** — Assert PARALLEL line contains `Skill(security-scanner)`.
8. **REVIEW sequence visible** — Assert REVIEW output contains SEQUENCE entries for requesting-code-review, agent-team-review, and receiving-code-review.

## Non-Goals

- No PreToolUse hooks for phase enforcement (design debate rejected this approach)
- No state-machine for phase completion tracking (tracked for future escalation)
- No changes to superpowers skill content

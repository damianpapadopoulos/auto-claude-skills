# Design: Stickiness Gate Guard + Remaining Review Fixes

## Overview

Fix the IMPLEMENT stickiness rule's violation of the superpowers brainstorming HARD-GATE, plus 5 remaining issues from the retroactive code review.

## Motivation

The IMPLEMENT stickiness rule (commit `5447671`) was designed to prevent DESIGN snap-back during mid-implementation work. However, it uses generic build verbs (`add|build|create|implement|...`) that also match new design intents. When a developer in IMPLEMENT phase says "let me build a new feature", the stickiness rule injects `executing-plans` above `brainstorming`, bypassing the superpowers HARD-GATE:

> "Do NOT invoke any implementation skill, write any code, scaffold any project, or take any implementation action until you have presented a design and the user has approved it."

The fix: restrict stickiness to explicit plan-continuation language only — the same language that `executing-plans` already uses as its own triggers.

## 1. Stickiness Gate Guard (Critical)

### Current logic (broken)

```
IF last_phase == IMPLEMENT
AND prompt matches (add|build|create|implement|modify|change|refactor|...)
AND prompt does NOT match (how.should|brainstorm|design|architect|...)
THEN inject executing-plans above top process
```

This matches "build a new authentication system" (new design intent) because "build" is a continuation verb and the prompt has no design blockers.

### Fixed logic

```
IF last_phase == IMPLEMENT
AND prompt matches EXPLICIT CONTINUATION language:
  (continue|resume|next.task|next.step|pick.up|carry.on|keep.going|
   where.were.we|what.s.next|move.on|proceed|finish.up|wrap.up.this|
   remaining|let.s.go|back.to.it)
THEN inject executing-plans above top process
```

Key change: **remove all generic build/create/add/modify verbs**. Only explicit continuation phrases trigger stickiness. This ensures:
- "continue with the next task" → stickiness fires (correct)
- "add error handling" → brainstorming fires (correct — HARD-GATE enforced)
- "build a new feature" → brainstorming fires (correct — HARD-GATE enforced)

The design-cue blockers (`how.should|brainstorm|design|architect`) become unnecessary and are removed (the continuation-only pattern already excludes design intents).

### Location

`hooks/skill-activation-hook.sh` — `_apply_context_bonus()`, lines 294-354.

## 2. Empty Tentative Phase Guard (Issue 3)

### Problem

When only domain skills score (no process/workflow), `_TENTATIVE_PHASE` is empty. Pass 0 then drops all required skills because `[[ "$phase" != "" ]]` is true for any non-empty required phase.

### Fix

After the tentative phase loop, if `_TENTATIVE_PHASE` is still empty and `_TENTATIVE_PHASE_REQUIRED` is set, use the required phase. This already exists partially — verify the fallback line `[[ -z "$_TENTATIVE_PHASE" ]] && _TENTATIVE_PHASE="$_TENTATIVE_PHASE_REQUIRED"` handles this correctly.

### Location

`hooks/skill-activation-hook.sh`, lines 1060-1084.

## 3. TDD Fallback Grep Subprocess (Issue 5)

### Problem

`grep -q 'test-driven-development'` runs on every IMPLEMENT/DEBUG prompt as a subprocess. Unnecessary fork.

### Fix

Track whether TDD was emitted from the jq composition path with a flag variable. Set `_TDD_EMITTED=1` inside the composition output loop when a line contains `test-driven-development`. Check the flag instead of forking grep.

### Location

`hooks/skill-activation-hook.sh`, lines 1095-1130 (composition output loop) and 1205-1213 (TDD fallback).

## 4. Agent-Team-Execution Duplicate Trigger (Issue 6)

### Problem

`agent-team-execution` shares the `execute.*plan|continue|resume|next.task|...` trigger pattern with `executing-plans`. Every continuation prompt co-selects both, which is noisy for simple continuations.

### Fix

Remove the second trigger from `agent-team-execution`. Keep only the team-specific trigger:
```json
"triggers": ["(agent.team|team.execute|parallel.team|swarm|fan.out|specialist|multi.agent)"]
```

The `requires: ["writing-plans"]` link + context bonus already ensures it appears after plan completion.

### Location

`config/default-triggers.json`, agent-team-execution entry.

## 5. Security-Scanner Test Brittleness (Issue 4)

### Problem

`test_security_scanner_review_parallel` passes even when fallback registry is loaded (where security-scanner has empty triggers and never scores as domain). The "not scored as domain" assertion passes for the wrong reason.

### Fix

Add an additional assertion that verifies the `PARALLEL:` line contains the correct invoke pattern, not just the skill name.

### Location

`tests/test-context.sh`, security-scanner test function.

## 6. Zero-Match Log Size Cap (Issue 7)

### Problem

Zero-match log rotates by line count (100 lines) but a single line can be arbitrarily long (full prompt text). Long prompts can grow the log unboundedly between rotations.

### Fix

Add a byte-size check before writing: if the log exceeds 50KB, rotate immediately regardless of line count. Truncate individual prompt entries to 200 characters.

### Location

`hooks/skill-activation-hook.sh`, lines 870-880.

## 7. Files to Modify

| File | Change |
|------|--------|
| `hooks/skill-activation-hook.sh` | Restrict stickiness to continuation language (S1); replace TDD fallback grep with flag (3); add log size cap + prompt truncation (6) |
| `config/default-triggers.json` | Remove duplicate trigger from agent-team-execution (4) |
| `config/fallback-registry.json` | Regenerate |
| `tests/test-routing.sh` | Update stickiness test prompt; add test for new-design-during-IMPLEMENT; update agent-team-execution fixture |
| `tests/test-context.sh` | Tighten security-scanner test assertion (5) |

## 8. Tests

1. **Stickiness on continuation** — Last phase IMPLEMENT + "continue with the next task". Assert executing-plans selected.
2. **New design during IMPLEMENT** — Last phase IMPLEMENT + "build a new authentication system". Assert brainstorming selected (HARD-GATE respected).
3. **Stickiness on resume** — Last phase IMPLEMENT + "pick up where we left off". Assert executing-plans selected.
4. **Agent-team-execution only on team language** — "continue with the next task" does NOT co-select agent-team-execution.
5. **TDD fallback without grep** — IMPLEMENT phase with composition lines present. Assert TDD line exists without additional subprocess.
6. **Zero-match log truncation** — Long prompt (500+ chars) produces truncated log entry.

## Non-Goals

- No changes to brainstorming trigger breadth — the HARD-GATE requires broad matching on build intents. The stickiness fix is the correct place to add precision, not the brainstorming triggers.
- No changes to name-boost segment scoring — tracked separately.
- No changes to the SDLC chain or required role mechanism.

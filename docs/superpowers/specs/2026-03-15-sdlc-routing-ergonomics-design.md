# Design: SDLC Routing Ergonomics

## Overview

Improve routing accuracy and developer experience without redesigning the phase model. Make PLAN directly reachable, make review-feedback prompts route correctly, stop mid-IMPLEMENT prompts from snapping back to DESIGN, and fix correctness issues in the fallback registry, composition state, and test infrastructure.

## Motivation

The agent-team review identified that the SDLC wiring is fundamentally sound (end-to-end chain, required-role bypass, phase compositions all working), but routing ergonomics need improvement:

1. **Mid-IMPLEMENT snap-back** — A developer 30 messages into IMPLEMENT saying "add error handling" gets `brainstorming` (DESIGN) because `add` matches brainstorming's broad triggers. The system has no session-phase awareness.
2. **PLAN unreachable** — `writing-plans` has zero triggers. "Write me a plan" routes to `brainstorming` instead.
3. **Review-feedback unroutable** — `receiving-code-review` has zero triggers. "Address the review comments" routes to `requesting-code-review` (wrong direction).
4. **Fallback registry drift** — `config/fallback-registry.json` is materially out of sync: security-scanner still as domain, git-worktrees as workflow, missing chain links. Routing changes based on cache state.
5. **Composition state corruption** — `_current_idx=-1` gets persisted when chain anchor isn't found, corrupting the chain display for the session.
6. **Test infrastructure gaps** — Phantom test function, fixtures diverged from production config, max_suggestions assertion counts wrong elements.

## 1. IMPLEMENT Stickiness Rule

### Location

`hooks/skill-activation-hook.sh` — extend `_apply_context_bonus()`.

### Logic

If:
- Last persisted phase (from `~/.claude/.skill-last-invoked-${TOKEN}`) is IMPLEMENT
- Current top process phase (from SORTED) is DESIGN or empty
- Prompt matches continuation/edit verbs: `(^|[^a-z])(add|build|create|implement|modify|change|refactor|wire.?up|connect|integrate|extend|update|rename|extract|move|replace)($|[^a-z])`
- Prompt does NOT match design/discovery cues: `(how.should|what.approach|best.way.to|ideas.for|options.for|trade.?off|compare|brainstorm|design|architect)`

Then: inject or raise `executing-plans` so it scores 5 points above the current top process skill.

### Why this specific approach

- Scoped to IMPLEMENT→DESIGN snap-back only (the most common friction point)
- Explicit exclusion of design-cue keywords preserves genuine phase transitions
- +5 above current top (not a fixed boost) ensures it wins regardless of brainstorming's score
- Reads from the already-persisted session state file — no new state mechanism

## 2. Registry Changes

### 2a. Add triggers to `writing-plans`

```json
"triggers": [
  "(plan( it)? out|write.*plan|implementation plan|break.?down|outline|task list|spec( it)? out)"
]
```

Makes PLAN phase independently reachable. Avoids false positives on "plan" as a noun (requires "plan out", "plan it out", or compound phrases).

### 2b. Add triggers to `receiving-code-review` + raise priority to 33

```json
"triggers": [
  "(review comments|pr comments|feedback|nits?|changes requested|address (the )?(review|comments|feedback)|respond to review|follow.?up review|re.?request review)"
],
"priority": 33
```

Priority 33 beats `requesting-code-review` (25) on feedback-intent prompts. The trigger set covers natural review-response vocabulary.

### 2c. Narrow brainstorming triggers

Split into high-signal intent regex plus boundary-safe generic verbs:

```json
"triggers": [
  "(brainstorm|design|architect|strateg|scope|outline|approach|set.?up|wire.up|how.(should|would|could))",
  "(^|[^a-z])(build|create|implement|develop|scaffold|init|bootstrap|introduce|enable|add|make|new|start)($|[^a-z])"
]
```

The second regex requires word-boundary anchors, preventing substring matches. The broad verbs `add|make|new|start` are still present but boundary-safe, so they only fire on whole-word matches — not as substrings in other words.

### 2d. Narrow design-debate triggers

Replace broad build verbs with explicit tradeoff/comparison triggers:

```json
"triggers": [
  "(trade.?off|debate|compare.*(option|approach|design)|weigh.*(option|approach)|pro.?con|alternative|architecture)"
]
```

### 2e. Narrow agent-team-execution triggers

Remove broad verbs `build|create|add|make` that blur the PLAN/IMPLEMENT boundary:

```json
"triggers": [
  "(agent.team|team.execute|parallel.team|swarm|fan.out|specialist|multi.agent)",
  "(execute.*plan|run.the.plan|implement.the.plan|implement.*(rest|remaining)|continue|follow.the.plan|pick.up|resume|next.task|next.step|carry.on|keep.going|where.were.we|what.s.next)"
]
```

## 3. Composition State Guard

### Location

`hooks/skill-activation-hook.sh` — `_walk_composition_chain()`.

### Fix

When `_current_idx` remains `-1` after the chain-anchor search:
- Clear composition output (`COMPOSITION_CHAIN=""`)
- Skip composition-state persistence (don't write the state file)

```bash
if [[ "$_current_idx" -lt 0 ]]; then
  # Anchor not found in chain — clear composition to avoid corrupted display
  COMPOSITION_CHAIN=""
  _full_chain=""  # prevents state file write
fi
```

The existing state-write guard at lines 889-901 checks `_full_chain` containing `|`, so clearing it prevents the write.

## 4. Test Infrastructure Fixes

### 4a. Fix max_suggestions assertion

Count `Process:|Domain:|Workflow:|Required:` lines, not `Skill(` occurrences. PARALLEL lines should not inflate the count.

### 4b. Remove phantom test function call

`test_skill_debug_stderr` at line 2262 of test-routing.sh calls a function that doesn't exist. Remove the call or implement the function.

### 4c. Regenerate fallback registry

Run session-start to regenerate `config/fallback-registry.json` from the current `default-triggers.json`, ensuring:
- security-scanner is NOT in skills[] (it's a composition parallel)
- using-git-worktrees has `role: "required"` with triggers
- agent-team-review has `role: "required"` with `required_when`
- Chain links present on executing-plans, requesting-code-review, verification-before-completion

### 4d. Add fallback-parity test

Add a test that validates key structural fields (role, phase, precedes, requires) match between the fallback registry and the cached registry after session-start runs.

## 5. Files to Modify

| File | Change |
|------|--------|
| `hooks/skill-activation-hook.sh` | IMPLEMENT stickiness rule in `_apply_context_bonus()`; `_current_idx` guard in `_walk_composition_chain()`; fix domain hint when no domains displayed |
| `config/default-triggers.json` | Add triggers to `writing-plans`; add triggers + priority 33 to `receiving-code-review`; narrow `brainstorming` triggers; narrow `design-debate` triggers; narrow `agent-team-execution` triggers |
| `config/fallback-registry.json` | Regenerate from current config |
| `tests/test-routing.sh` | Fix max_suggestions assertion; remove phantom `test_skill_debug_stderr`; add tests for PLAN routing, IMPLEMENT stickiness, review-feedback routing, composition-state guard, design-debate narrowing; update fixtures for chain links and review triggers |
| `tests/test-registry.sh` | Add fallback-parity test for structural fields |

## 6. Tests

### New tests

1. **Direct PLAN prompt selects writing-plans** — "let's plan this out" with no prior chain state. Assert writing-plans selected.
2. **IMPLEMENT stickiness** — Last phase IMPLEMENT + "add error handling to the auth module". Assert executing-plans selected, not brainstorming.
3. **Stickiness respects design cues** — Last phase IMPLEMENT + "how should we architect the error handling?". Assert brainstorming selected (design cue overrides stickiness).
4. **Review-feedback selects receiving-code-review** — "address the review comments on the PR". Assert receiving-code-review selected, not requesting-code-review.
5. **Design-debate only on tradeoff language** — "add a new endpoint" should NOT trigger design-debate. "compare the two architecture approaches" should.
6. **Composition state not corrupted** — Force missing chain anchor. Assert no state file written with `current_index: -1`.
7. **Fallback registry parity** — Key fields match between fallback and cached registry.

### Existing test fixes

8. **max_suggestions assertion** — Count role-prefixed lines only.
9. **Remove phantom test_skill_debug_stderr** — Delete or implement.

## Non-Goals

- No phase-model redesign. The chain, required role, and DEBUG side-loop are unchanged.
- No changes to `subagent-driven-development` role or triggers.
- No changes to methodology hints (openspec-ship-reminder redundancy is low priority, deferred).
- No changes to session-start-hook.sh beyond fallback regeneration.

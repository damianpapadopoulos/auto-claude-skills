# Phase-Gated SDLC Enforcement

## Problem

Claude skips the superpowers SDLC path (brainstorming -> writing-plans -> executing-plans) and jumps directly to implementation. Three failure modes:

1. **"EVALUATE YES/NO" framing** lets Claude say "brainstorming NO" and skip design phase
2. **Composition chain sometimes missing** from hook output in certain format paths
3. **Transitions between phases lost** — after brainstorming completes, no signal points to writing-plans

## Root Cause

The hook infrastructure (scoring, chain walking, composition state) works correctly. The single failure point is the instruction language in `_format_output()` — it presents process skills as optional ("EVALUATE YES/NO") when they should be mandatory for phase-matching prompts.

## Design

Three changes, all in `hooks/skill-activation-hook.sh`, instruction layer only.

### Change 1: Phase-gated evaluation language

When the selected process skill matched triggers (score > 0), it is phase-appropriate for the prompt. The evaluation line changes from `YES/NO` to `MUST INVOKE`:

```
# Before (all formats):
Evaluate: brainstorming YES/NO, design-debate YES/NO

# After:
Process: brainstorming -> MUST INVOKE (DESIGN phase)
  Domain: design-debate YES/NO
```

The gate is inherently phase-aware: brainstorming only gets selected when build-intent triggers match. No additional phase detection needed.

Applies to all four format paths: full (3+ skills, prompt 1), compact (1-2 skills, depth 1-5), compact (depth 6-10), minimal (depth 11+).

### Change 2: Always display composition chain and directive

Remove the display gate at line 568:
```bash
# Before:
if [[ "$_full_chain" == *"|"* ]]; then

# After:
if [[ -n "$_full_chain" ]]; then
```

The chain walk produces `brainstorming|writing-plans|executing-plans` when a process skill has `precedes`. The `*"|"*` gate is redundant for valid chains but suppresses output silently when the forward walk returns only the anchor (jq error, missing registry entry). Changing to `-n` ensures the chain always displays when any chain exists, even a single-skill one.

Also ensure `COMPOSITION_DIRECTIVE` appears in all format paths that include `${COMPOSITION_CHAIN}`.

### Change 3: Strengthen Step 3 in full format

```
# Before:
Step 3 -- State your plan and proceed.

# After:
Step 3 -- INVOKE the process skill. Do not skip to a later phase.
```

## What stays the same

- Scoring engine unchanged
- Role-cap selection unchanged
- Registry config (default-triggers.json) unchanged
- Composition state persistence unchanged
- Zero-match path stays silent
- Context bonus mechanism unchanged

## Files touched

`hooks/skill-activation-hook.sh` only

## Testing

- `bash tests/run-tests.sh` — all existing tests pass
- Manual: `echo '{"prompt":"build a login system"}' | SKILL_EXPLAIN=1 bash hooks/skill-activation-hook.sh` — verify "MUST INVOKE" in output
- Manual: `echo '{"prompt":"why is this broken"}' | SKILL_EXPLAIN=1 bash hooks/skill-activation-hook.sh` — verify debugging gets MUST INVOKE, not brainstorming
- Manual: `echo '{"prompt":"yes lets do it"}' | bash hooks/skill-activation-hook.sh` — verify zero-match stays silent (no regression)

## Success criteria

1. "build a login system" produces `MUST INVOKE` for brainstorming, with full composition chain visible
2. "debug this crash" produces `MUST INVOKE` for systematic-debugging, no brainstorming
3. Composition chain and directive appear in all format paths when a process skill with `precedes` is selected
4. All existing tests pass

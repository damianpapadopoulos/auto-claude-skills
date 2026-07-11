# Design: DISCOVER-before-DESIGN precondition in composition step text

## Architecture

The composition chain is rendered in `hooks/skill-activation-hook.sh`. A jq batch-lookup
(~line 833) builds one `name<FS>invoke<FS>desc<FS>phase` row per chain skill, where
`desc = (.description | split(".")[0])` (first sentence only). A `while` loop (~line 877)
prints each row as `[MARKER] Step N: <invoke> -- <desc>`, with MARKER ∈ DONE/CURRENT/NEXT/LATER.

**Change:** carry an optional `precondition` string through the batch-lookup, and in the
`_marker == CURRENT` branch emit one extra indented line immediately under the step:

```
  [CURRENT] Step 1: Skill(superpowers:brainstorming) -- Ask clarifying questions...
      PRECONDITION: if this is a new feature/initiative and no discovery brief exists
      (session-state discovery_path or docs/plans/*-discovery.md), invoke
      Skill(auto-claude-skills:product-discovery) FIRST, then return to brainstorming.
      Skip for bugfixes/small changes or when a brief exists.
```

CURRENT-only keeps it out of every LATER step and places it exactly where the model reads
"what do I do now." The conditional is **model-evaluated** — the hook always emits it on the
CURRENT brainstorming step; the "if no brief exists" text is what makes the model skip when a
brief is present (measured 5/5 no-over-fire).

### Why not the alternatives (rejected)
- **Append to `description`:** the renderer truncates to the first sentence (`split(".")[0]`),
  and paths like `docs/plans/*-discovery.md` contain periods that would break the split. It
  would also pollute the other two surfaces that read `description` (catalog, breadcrumb).
- **Keep the hint, reword it:** measured causally zero (0/5). Rewording the same channel
  can't beat mandatory step text.
- **Rung-2 walker re-anchor** (prepend product-discovery to the chain deterministically):
  stronger but heavier; kept as the documented escalation if step-text under-routes.

## Trade-offs / Decisions

- **Model-conditional only (no deterministic suppression) — MVP.** Matches exactly what was
  measured 5/5 (no over-fire). A deterministic "omit when session-state `discovery_path` set"
  guard is deferred; revival trigger: the uptake eval shows over-fire when a brief exists.
- **Scope: `brainstorming` only.** The measured, common DESIGN entry. `design-debate` (rare
  alt driver) is out of scope; revival trigger: design-debate becomes a common entry.
- **General `precondition` field, one consumer.** Minimal generality — reusable later, but
  only `brainstorming` uses it now (YAGNI-bounded).

## Dissenting views

- "A second CURRENT-step line adds context noise." Mitigation: CURRENT-only (one step, one
  line) and it replaces a hint line that was already in every DESIGN context — net token
  change ≈ neutral, and the eval justifies the placement.

## How this is verified (eval strategy)

This is agent-behavior (does the model take up the precondition?). A config-assert/grep
proves NOTHING about uptake (the #102 lesson). Acceptance = two layers:
1. **Deterministic** (unit): the precondition line renders on the CURRENT brainstorming step,
   is absent on LATER/DONE steps and when the field is unset, and doesn't break existing
   composition rendering.
2. **Uptake eval** (the real bar): replay the composition context with arm B (precondition)
   vs arm A (old hint baseline, expect ~0/5) and a brief-exists control; require the
   precondition arm to route to product-discovery first-invoke ≥4/5 and the control to
   correctly skip ≥4/5. Red-first: baseline arm demonstrates the 0/5 it replaces.

## Out-of-scope

Deterministic session-state suppression; design-debate; rung-2 walker re-anchor; any change
to the assumption-audit content shipped in #102.

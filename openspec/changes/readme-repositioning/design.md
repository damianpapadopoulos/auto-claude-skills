# Design: README Repositioning

## Architecture
Single-file rewrite of README.md following a decision-funnel structure (Approach A) with SDLC phase-awareness (Approach C element). 10 sections ordered to answer visitor questions progressively. All claims verified against codebase before writing.

## Dependencies
None. Markdown-only change with no code dependencies.

## Decisions & Trade-offs

**Decision: Product page funnel (A) over minimal landing page (B) or SDLC-organized (C).**
- A respects visitor time by front-loading value while explaining enough to build trust.
- B was too terse to evaluate (pushes detail to a separate doc visitors won't click).
- C assumed readers already think in SDLC phases; visitors want "what does this do for me" first.
- Compromise: A as the spine with C's phase table woven into "What It Does."

**Decision: No brittle counts.**
- Old README had "4 bundled skills," "23 total routed skills," "12 companion plugins" — all go stale on any skill addition.
- Replaced with category descriptions and a scope flavor line.

**Decision: Drop the "fallthrough assessment" claim.**
- Old README claimed unmatched development prompts trigger "Claude assesses from context."
- Verified against code: zero matches = silent exit, no assessment. Claim was inaccurate.

**Decision: Merge prerequisites into Install section.**
- Old README had a standalone Prerequisites section at the bottom. Folded into Install for decision-funnel flow.

# Design: Incident Analysis Critique Fixes

## Architecture
No architectural changes. All modifications are to the behavioral specification (SKILL.md), its contract (spec.md), and their regression tests. The runtime hook system, registry, and scoring engine are unaffected.

## Dependencies
None introduced.

## Decisions & Trade-offs

**Constraint 2 carve-out placement:** The infrastructure escalation exception was placed directly in Constraint 2 (not in Step 3 where the escalation logic lives) so the agent encounters the permission before it encounters any stage. This front-loads the exception where behavioral constraints are defined.

**Step 7 synthesis scope:** Rather than relaxing Constraint 4 (which forbids referencing raw logs after synthesis), the synthesis instruction was expanded to require preserving all investigation artifacts. This keeps the context discipline intact while ensuring the Investigation Path appendix has sufficient material.

**Evidence persistence as imperative steps:** The Evidence Bundle section already described what to persist, but as a reference appendix. Adding explicit "write pre.json" and "write validate.json" steps in the EXECUTE/VALIDATE flows makes persistence a mandatory part of the execution sequence rather than an optional reference.

**Test needle capitalization:** Step 7 items 3-4 use lowercase bold labels to match the case-sensitive test assertions. This is a pragmatic choice — the behavioral content is identical regardless of capitalization.

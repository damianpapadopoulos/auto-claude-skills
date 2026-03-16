# Proposal: Design Phase Context Stack

## Problem Statement
The unified-context-stack had phase documents for Plan, Implement, Test & Debug, Code Review, and Ship & Learn — but none for DESIGN (brainstorming). The activation hook declared the context stack as a PARALLEL during DESIGN, but the hint text was generic ("Gather curated API docs, map dependencies, check institutional memory") and didn't distinguish which tiers matter during brainstorming vs planning. This meant brainstorming proposed approaches without checking existing specs or past architectural decisions.

## Proposed Solution
Add a `phases/design.md` phase document with only Intent Truth and Historical Truth — the two tiers that inform what to propose. Narrow the activation hook's DESIGN-phase hint from all 4 tiers to these 2 specifically. External Truth (API docs) and Internal Truth (blast-radius mapping) remain deferred to the Plan phase.

## Out of Scope
- Modifying the upstream `brainstorming` skill (owned by superpowers plugin)
- Adding new capability flags or hook logic
- Changing the `triage-and-plan.md` phase doc (still covers all 4 tiers during plan-writing)

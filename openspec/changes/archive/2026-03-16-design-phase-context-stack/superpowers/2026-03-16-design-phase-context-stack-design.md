# Design Phase Context Stack Integration

## Problem

The unified-context-stack has phase docs for Plan, Implement, Test & Debug, Code Review, and Ship & Learn — but none for DESIGN (brainstorming). The activation hook already declares the context stack as a PARALLEL during DESIGN, but there is no phase doc to guide which tiers to use. The current hint text is generic and doesn't distinguish which tiers matter during brainstorming vs planning.

This means brainstorming proposes approaches without checking whether existing specs or past architectural decisions already constrain the design space — wasting a full brainstorming cycle if plan-writing later reveals a conflict.

## Solution

### Selective tier integration

Only Intent Truth and Historical Truth belong in the DESIGN phase. External Truth and Internal Truth are deferred to Plan.

| Tier | DESIGN? | Rationale |
|------|:---:|---|
| Intent Truth | Yes | Existing specs on this capability must be known before proposing approaches |
| Historical Truth | Yes | Past decisions and constraints shape which approaches are viable |
| External Truth | No | Library/API choice depends on the chosen approach — premature during brainstorming |
| Internal Truth | No | Blast radius depends on which files will be touched — premature during brainstorming |

### Changes

**1. New file: `skills/unified-context-stack/phases/design.md`**

Two steps, mirroring triage-and-plan Steps 0-1 but scoped to DESIGN:

- **Step 0: Intent Truth** — check `openspec/changes/<feature>/`, `openspec/specs/<capability>/spec.md`, and `docs/superpowers/specs/` for existing specifications. Carry forward requirements as constraints on proposed approaches.
- **Step 1: Historical Truth** — query Forgetful Memory (`memory-search`) for past architectural decisions and constraints in this area; fallback to CLAUDE.md, `docs/architecture.md`, `.cursorrules`.

Explicitly note that External Truth and Internal Truth are deferred to the Plan phase.

**2. Modified: `skills/unified-context-stack/SKILL.md`**

Add `design.md` to the Phase Documents list, before `triage-and-plan.md`:
```
- [Design](phases/design.md) — Intent and historical context before proposing approaches
```

**3. Modified: `config/default-triggers.json` — DESIGN phase composition**

Narrow the parallel entry fields:
- `use`: `"tiered context retrieval (Intent Truth, Historical Truth)"` (was: `"tiered context retrieval (external docs, blast-radius, memory)"`)
- `purpose`: `"Check existing specs and past decisions before proposing approaches"` (was: `"Gather curated API docs, map dependencies, check institutional memory during design"`)

### What doesn't change

- The `brainstorming` skill (upstream, not ours)
- `triage-and-plan.md` (still covers all 4 tiers during plan-writing)
- Hook emission logic (already reads `purpose` from `phase_compositions`)
- Fallback registry structure (manually mirrored from default-triggers.json — `use`/`purpose` fields updated in both)

## Scope

4 files (1 new, 3 modified). No hook logic changes. No new capabilities.
